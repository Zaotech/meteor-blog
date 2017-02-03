

Blog.Router =
  routes: []

  getNotFoundTemplate: ->
    if Package['iron:router']
      Router.lookupNotFoundTemplate()

  notFound: ->
    if Package['kadira:flow-router']
      FlowRouter._notfoundRoute FlowRouter.current()

  replaceState: (path) ->
    if Package['iron:router']
      Iron.Location.go path, { replaceState: true, skipReactive: true }
    else if Package['kadira:flow-router']
      FlowRouter.withReplaceState -> FlowRouter.go path

  go: (nameOrPath, params, options) ->
    router =
      if Package['iron:router']
        Package['iron:router'].Router
      else if Package['kadira:flow-router']
        Package['kadira:flow-router'].FlowRouter

    if /^\/|http/.test(nameOrPath)
      path = nameOrPath
    else
      route = _.findWhere @routes, name: nameOrPath
      if not route
        throw new Meteor.Error 500, "Route named '#{nameOrPath}' not found"
      options ?= {}
      url = new Iron.Url route.path
      path = url.resolve params, options
    router.go path

  getLocation: ->
    if Package['iron:router']
      location = Router.current().url
      if location.slice(0, 4) == 'http'
        # Remove base url because we only want the path after it
        baseURL = Meteor.absoluteUrl()
        location = location.slice(baseURL.length-1, location.length)
      #'/' + Router.current().params[0]
    else if Package['kadira:flow-router']
      FlowRouter.watchPathChange()
      FlowRouter.current().path

  getParam: (key) ->
    if Package['iron:router']
      return Router.current().params[key]

    location = @getLocation()
    url = null
    match = _.find @routes, (route) ->
      url = new Iron.Url route.path
      url.test location
    if match
      params = url.params(location)
      return params[key]

  pathFor: (name, params, options) ->
    route = _.findWhere @routes, name: name
    if not route
      throw new Meteor.Error 500, "Route named '#{name}' not found"
    opts = options and (options.hash or {})
    url = new Iron.Url route.path
    url.resolve params, opts

  getTemplate: (location) ->
    location = location or @getLocation()
    url = null
    match = _.find @routes, (route) ->
      url = new Iron.Url route.path
      url.test location
    if match
      name = match.name

      # Tagged view uses 'blogIndex' template
      if name is 'blogTagged'
        name = 'blogIndex'

      # Custom template?
      if Blog.settings["#{name}Template"]
        name = Blog.settings["#{name}Template"]
      return name

  routeAll: (routes) ->
    @routes = routes

    basePath =
      # Avoid double-slashes like '//tag/:tag' when basePath is '/'...
      if Blog.settings.basePath is '/'
        ''
      else
        Blog.settings.basePath
    adminBasePath =
      if Blog.settings.adminBasePath is '/'
        ''
      else
        Blog.settings.adminBasePath

    # --------------------------------------------------------------------------
    # IRON ROUTER

    if Package['iron:router']
      # Fast Render
      if Meteor.isServer
        routes.forEach (route) ->
          if route.fastRender
            FastRender.route route.path, route.fastRender

      catchAll = _.findWhere(Package['iron:router'].Router.routes, _path: '/(.*)')
      if catchAll
        # If app has already defined a catch-all route, prepend our logic to its
        # before hook

        catchAllHook = catchAll.options.onBeforeAction
        return catchAll.options.onBeforeAction = ->
          template = Blog.Router.getTemplate()
          if template
            if Blog.settings.blogLayoutTemplate
              @layout Blog.settings.blogLayoutTemplate
            @render template
          else if catchAllHook
            catchAllHook.call @
          else
            @next()

      _.each(routes, (route) ->
        Package['iron:router'].Router.route route.path,
          onBeforeAction: ->
            template = Blog.Router.getTemplate(route.path)
            if template
              if Blog.settings.blogLayoutTemplate
                @layout Blog.settings.blogLayoutTemplate
              @render template
            else
              @next()
          action: ->
            @next()
          seo: route.seo
          subscriptions: ->
            # Wait for the necessary subscriptions for individual blog post page.
            route.subscriptions()
      )

    # --------------------------------------------------------------------------
    # FLOW ROUTER

    else if Package['kadira:flow-router']
      Package['kadira:flow-router'].FlowRouter.route '/:any*',
        action: ->
          template = Blog.Router.getTemplate()
          if template
            if Blog.settings.blogLayoutTemplate
              layout = Blog.settings.blogLayoutTemplate
              BlazeLayout.render layout, template: template
            else
              BlazeLayout.render template
          else
            Blog.Router.notFound()


    else
      throw new Meteor.Error 500, 'Blog requires either iron:router or kadira:flow-router'
 
 
if Package['kadira:flow-router']
  Package['kadira:flow-router'].FlowRouter.wait()

Meteor.startup ->

  routes = []
  basePath =
    # Avoid double-slashes like '//tag/:tag' when basePath is '/'...
    if Blog.settings.basePath is '/'
      ''
    else
      Blog.settings.basePath
  adminBasePath =
    if Blog.settings.adminBasePath is '/'
      ''
    else
      Blog.settings.adminBasePath


  # ----------------------------------------------------------------------------
  # PUBLIC ROUTES


  # BLOG INDEX

  routes.push
    path: basePath or '/' # ...but ensure we don't have a route path of ''
    name: 'blogIndex'
    fastRender: ->
      @subscribe 'blog.authors'
      @subscribe 'blog.posts'
    seo:
      description: Blog.settings.description
      image: ->
        # Show image of most recent blog post
        post = Blog.Post.first()
        post.thumbnail() if post
      og:
        type: 'website'
      title: Blog.settings.title
    subscriptions: ->
      [
        Meteor.subscribe 'blog.authors'
        Meteor.subscribe 'blog.posts'
      ]

  # BLOG TAG

  routes.push
    path: basePath + '/tag/:tag'
    name: 'blogTagged'
    fastRender: (params) ->
      @subscribe 'blog.authors'
      @subscribe 'blog.taggedPosts', params.tag
    seo:
      description: ->
        tag = Blog.Router.getParam 'tag'
        'Posts tagged with "' + tag + '".'
      image: ->
        tag = Blog.Router.getParam 'tag'
        post = Blog.Post.first tag: tag
        post.thumbnail() if post
      og:
        type: 'article'
      title: ->
        tag = Blog.Router.getParam 'tag'
        '"' + tag + '" posts'
    subscriptions: ->
      tag = Blog.Router.getParam 'tag'
      [
        Meteor.subscribe 'blog.authors'
        Meteor.subscribe 'blog.taggedPosts', tag
      ]

  # SHOW BLOG

  routes.push
    path: basePath + '/:slug'
    name: 'blogShow'
    fastRender: (params) ->
      @subscribe 'blog.authors'
      @subscribe 'blog.singlePostBySlug', params.slug
      @subscribe 'blog.commentsBySlug', params.slug
    seo:
      description: ->
        slug = Blog.Router.getParam 'slug'
        post = Blog.Post.first slug: slug
        getTranslatedString(post.excerpt) if post and post.excerpt
      image: ->
        slug = Blog.Router.getParam 'slug'
        post = Blog.Post.first slug: slug
        post.thumbnail() if post
      og:
        type: 'article'
      title: ->
        slug = Blog.Router.getParam 'slug'
        post = Blog.Post.first slug: slug
        getTranslatedString(post.title) if post and post.title
    subscriptions: ->
      slug = Blog.Router.getParam 'slug'
      [
        Meteor.subscribe 'blog.singlePostBySlug', slug
        Meteor.subscribe 'blog.commentsBySlug', slug
        Meteor.subscribe 'blog.authors'
      ]


  # ----------------------------------------------------------------------------
  # ADMIN ROUTES


  # BLOG ADMIN INDEX

  routes.push
    path: adminBasePath
    name: 'blogAdmin'
    seo:
      title: Blog.settings.title + ' Admin'
    subscriptions: ->

  # NEW/EDIT BLOG

  routes.push
    path: adminBasePath + '/edit/:id'
    name: 'blogAdminEdit'
    seo:
      title: 'Edit Post'
    subscriptions: ->


  # ----------------------------------------------------------------------------
  # RSS


  if Meteor.isServer
    JsonRoutes.add 'GET', '/rss/posts', (req, res, next) ->
      res.write Meteor.call 'serveRSS'
      res.end()


  Blog.Router.routeAll routes

  if Package['kadira:flow-router']
    FlowRouter.initialize()
