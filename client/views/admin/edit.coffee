
# ------------------------------------------------------------------------------
# METHODS

getBlogTags = (tags) ->
  if typeof tags is 'string'
    []
  else
    # Remove empty tags
    cleanTags = tags.filter (tag) ->
      tag != ''
    cleanTags


# Reads image dimensions and takes a callback callback passes params (width,
# height, fileName)
readImageDimensions = (file, cb) ->
  reader = new FileReader
  image = new Image
  reader.readAsDataURL file

  reader.onload = (_file) ->
    image.src = _file.target.result

    image.onload = ->
      w = @width
      h = @height
      n = file.name
      cb(w,h,n) # callback with width, height as params
      return

    image.onerror = ->
      alert 'Invalid file type: ' + file.type


# Find tags using typeahead
substringMatcher = (strs) ->
  (q, cb) ->
    matches = []
    pattern = new RegExp q, 'i'

    _.each strs, (ele) ->
      if pattern.test ele
        matches.push
          val: ele

    cb matches

# Toggle between visual and HTML mode
setEditMode = (tpl, mode) ->
  tpl.$('.editable').toggle()
  tpl.$('.html-editor').toggle()
  tpl.$('.edit-mode a').removeClass 'selected'
  tpl.$(".#{mode}-toggle").addClass 'selected'

# Save
save = (tpl, cb) ->
  $form = tpl.$('form')
  editables = $('.editable', $form)
  editors = BlogEditor.make tpl
  bodyStringObject = {}

  for index in [0..editables.length-1]
    $editable = $(editables[index])
    editor = editors[index]

    # Make paragraphs commentable
    # remove duplicates
    $editable.find('p[data-section-id]').each ->
      sec_id = $(this).attr 'data-section-id'
      if $editable.find("p[data-section-id=#{sec_id}]").length > 1
        $editable.find("p[data-section-id=#{sec_id}]:gt(0)").removeAttr 'data-section-id'
    # decorate
    i = $editable.find('p[data-section-id]').length + 1
    $editable.find('p:not([data-section-id])').each ->
      $(this).addClass('commentable-section').attr('data-section-id', i)
      i++

    # Highlight code blocks
    editor.highlightSyntax()

    if $editable.is(':visible')
      body = editor.contents()
    else
      body = $('.html-editor', $form).val().trim()

    # If the body only contains whitespace and <br> tags, remove them.
    bodyOnlyContainsWhitespace = /^<p[a-zA-Z\s="\d-]*>[(<br\/?>|\\n|\s)]*<\/p>$/.test body
    body = '' if bodyOnlyContainsWhitespace or !body

    langCode = $editable.data('lang')
    if body?
      bodyNotNull = true # At least one body exists

    bodyStringObject[langCode] = body

  # If not at least one body exists, call the callback with an error.
  if not bodyNotNull
    return cb(null, new Error Blog.settings.language.editErrorBodyRequired)

  slug = $('[name=slug]', $form).val()

  attrs =
    title: convertNodesToStringObject($('[name=title]', $form))
    tags: getBlogTags($('[name=tags]', $form).val().split(','))
    slug: slug
    description: $('[name=description]', $form).val()
    body: bodyStringObject
    updatedAt: new Date()
    titleBackground: $('[name=background-title]', $form).is(':checked')

  attrs.featuredImageWidth = Session.get('blog.featuredImageWidth')
  attrs.featuredImageHeight = Session.get('blog.featuredImageHeight')
  attrs.featuredImageName = Session.get('blog.featuredImageName')
  attrs.featuredImage = Session.get('blog.featuredImage')

  post = Blog.Post.first(tpl.id.get())
  if post?
    post.update attrs
    if post.errors
      return cb(null, new Error _(post.errors[0]).values()[0])
    cb null

  else
    Meteor.call 'doesBlogExist', slug, (err, exists) ->
      if not exists
        attrs.userId = Meteor.userId()
        post = Blog.Post.create attrs
        if post.errors
          return cb(null, new Error _(post.errors[0]).values()[0])
        cb post.id
      else
        return cb(null, new Error Blog.settings.language.editErrorSlugExists)


# ------------------------------------------------------------------------------
# TEMPLATE CODE


Template.blogAdminEdit.onCreated ->
  @id = new ReactiveVar null
  @autorun =>
    @id.set Blog.Router.getParam 'id'

  postSub = null
  authorsSub = @subscribe 'blog.authors'
  tagsSub = @subscribe 'blog.postTags'

  @autorun =>
    postSub = @subscribe 'blog.singlePostById', @id.get()

  @subsReady = new ReactiveVar false
  @autorun =>
    if postSub.ready() and authorsSub.ready() and tagsSub.ready() and !Meteor.loggingIn()
      @subsReady.set true

  @autorun ->
    Blog.Router.go 'blogIndex' if not Meteor.userId()

  Session.set 'blog.featuredImageWidth', null
  Session.set 'blog.featuredImageHeight', null
  Session.set 'blog.featuredImageName', null
  Session.set 'blog.featuredImage', null


Template.blogAdminEdit.onRendered ->
  Meteor.call 'isBlogAuthorized', @id.get(), (err, authorized) =>
    if not authorized
      return Blog.Router.go('/blog')

  # We can't use reactive template vars for contenteditable :-(
  # (https://github.com/meteor/meteor/issues/1964). So we put the single-post
  # subscription in an autorun and update the contents the old-fashioned way via
  # jQuery.
  @autorun =>
    if @subsReady.get()
      Meteor.defer =>
        # Wait a tick for template to re-render
        post = Blog.Post.first(@id.get())
        if post?
          for language in getSupportedLanguages()
            # Load post body initially, if any
            @$('.editable[data-lang=' + language.code + ']').html post.body[language.code]
            @$('.html-editor[data-lang=' + language.code + ']').html post.body[language.code]

        # Tags
        $tags = @$('[data-role=tagsinput]')
        $tags.tagsinput
          confirmKeys: [13, 44, 9]
          onTagExists: (item, tag) ->
            # Tag already exists
            # Keep default behavior for tag to hide and fade in,
            # but also clear the typeahead input.
            tag.hide().fadeIn()
            $tags.tagsinput('input').typeahead 'val', ''
          trimValue: true
        $tags.on 'itemAdded', (e) ->
          # Clear input after tag is added.
          $(this).typeahead 'val', ''
        $tags.tagsinput('input').typeahead(
          highlight: true
          hint: false
        ,
          name: 'tags'
          display: 'val'
          source: substringMatcher Blog.Tag.first().tags
        ).bind 'typeahead:selected', (obj, datum) ->
          $tags.tagsinput 'add', datum.val

        # Create the Medium editor
        BlogEditor.make @

Template.blogAdminEdit.helpers
  post: ->
    post = Blog.Post.first(Template.instance().id.get())
    if post
      Session.set 'blog.featuredImageWidth', post.featuredImageWidth
      Session.set 'blog.featuredImageHeight', post.featuredImageHeight
      Session.set 'blog.featuredImageName', post.featuredImageName
      Session.set 'blog.featuredImage', post.featuredImage
      post
    else
      {}
  subsReady: -> Template.instance().subsReady.get()
  featuredImage: -> Session.get('blog.featuredImage')
  featuredImageName: -> Session.get('blog.featuredImageName')


Template.blogAdminEdit.events
  # Toggle between VISUAL/HTML modes
  'click [data-action=toggle-visual]': (e, tpl) ->
    if tpl.$('.editable').is(':visible')
      return

    for editor in BlogEditor.make(tpl)
      editor.highlightSyntax()
    setEditMode tpl, 'visual'

  'click [data-action=toggle-html]': (e, tpl) ->
    editables = tpl.$('.editable')
    htmls = tpl.$('.html-editor')
    if htmls.is(':visible')
      return

    editors = BlogEditor.make(tpl)
    for index in [0..editables.length-1]
      $editable = $(editables[index])
      $html = $(htmls[index])
      editor = editors[index]

      $html.val editor.pretty()
      $html.height($editable.height())

    setEditMode tpl, 'html'

  # Copy HTML content to visual editor and autosize height
  'keyup .html-editor': (e, tpl) ->
    editables = tpl.$('.editable')
    htmls = tpl.$('.html-editor')

    for index in [0..editables.length-1]
      $editable = $(editables[index])
      $html = $(htmls[index])

      $editable.html($html.val()?.trim())
      $html.height($editable.height())

  # Autosave
  'input .editable, keydown .editable, keydown .html-editor': _.debounce (e, tpl) ->
    if Blog.settings.autosave
      save tpl, (id, err) ->
        if err
          return toastr.error err.message

        if id
          # If new blog post, subscribe to the new post and update URL
          tpl.id.set id
          path = Blog.Router.pathFor 'blogAdminEdit', id: id
          Blog.Router.replaceState path

        toastr.success Blog.settings.language.saved
  , 8000

  'blur [name=title]': (e, tpl) ->
    slug = tpl.$('[name=slug]')
    title = $(e.currentTarget).val()

    if not slug.val()
      slug.val Blog.Post.slugify(title)

  'click [data-action=delete-featured]': (e, tpl) ->
    e.preventDefault()
    Session.set 'blog.featuredImageWidth', null
    Session.set 'blog.featuredImageHeight', null
    Session.set 'blog.featuredImageName', null
    Session.set 'blog.featuredImage', null

  'change [name=featured-image]': (e, tpl) ->
    the_file = $(e.currentTarget)[0].files[0]
    post = @
    # get dimensions
    readImageDimensions the_file, (width, height, name) ->
      Session.set 'blog.featuredImageWidth', width
      Session.set 'blog.featuredImageHeight', height
      Session.set 'blog.featuredImageName', name

    # S3
    if Meteor.settings?.public?.blog?.useS3
      Blog.S3Files.insert the_file, (err, fileObj) ->
        Tracker.autorun (c) ->
          theFile = Blog.S3Files.find({_id: fileObj._id}).fetch()[0]
          if theFile.isUploaded() and theFile.url?()
            Session.set 'blog.featuredImage', theFile.url()
            toastr.success Blog.settings.language.editFeaturedImageSaved
            c.stop()
    # Local Filestore
    else
      Blog.FilesLocal.insert the_file, (err, fileObj) ->
        Tracker.autorun (c) ->
          theFile = Blog.FilesLocal.find({_id: fileObj._id}).fetch()[0]
          if theFile.isUploaded() and theFile.url?()
            Session.set 'blog.featuredImage', theFile.url()
            toastr.success Blog.settings.language.editFeaturedImageSaved
            c.stop()

  'submit form': (e, tpl) ->
    e.preventDefault()
    save tpl, (id, err) ->
      if err
        return toastr.error err.message
      Blog.Router.go 'blogAdmin'
