################################################################################
# Bootstrap Code
#


Blog.subs = new SubsManager
  cacheLimit: 10, # Maximum number of cache subscriptions
  expireIn: 5 # Any subscription will be expire after 5 minute, if it's not subscribed again

Meteor.startup ->
  ShareIt.init Blog.settings.shareit

  if Blog.settings.syntaxHighlightingTheme
    # Syntax Highlighting
    $('<link>',
      href: '//cdnjs.cloudflare.com/ajax/libs/highlight.js/8.1/styles/' + Blog.settings.syntaxHighlightingTheme + '.min.css'
      rel: 'stylesheet'
    ).appendTo 'head'

  if Blog.settings.cdnFontAwesome
    # Load Font Awesome
    $('<link>',
      href: '//netdna.bootstrapcdn.com/font-awesome/4.3.0/css/font-awesome.css'
      rel: 'stylesheet'
    ).appendTo 'head'

  # Listen for any 'Load More' clicks
  $('body').on 'click', '.blog-load-more', (e) ->
    e.preventDefault()
    if Session.get 'blog.postLimit'
      Session.set 'blog.postLimit', Session.get('blog.postLimit') + Blog.settings.pageSize

################################################################################
# Register Global Helpers
#

Template.registerHelper 'BlogLanguage', () ->
  return Blog.settings.language

Template.registerHelper "blogFormatDate", (date) ->
  moment(new Date(date)).format Blog.settings.dateFormat

Template.registerHelper "blogFormatTags", (tags) ->
  return if !tags?

  for tag in tags
    path = Blog.Router.pathFor 'blogTagged', tag: tag
    if str?
      str += ", <a href=\"#{path}\">#{tag}</a>"
    else
      str = "<a href=\"#{path}\">#{tag}</a>"
  return new Spacebars.SafeString str

Template.registerHelper "blogJoinTags", (list) ->
  if list
    list.join ', '

Template.registerHelper "blogPager", ->
  if Blog.Post.count() is Session.get 'blog.postLimit'
    loadMore = Blog.settings.language.loadMore
    return new Spacebars.SafeString '<a class="blog-load-more btn" href="#">' + loadMore + '</a>'

Template.registerHelper 'blogPathFor', (name, options) ->
  return Blog.Router.pathFor name, @, options

Template.registerHelper "getTranslatedString", (stringObject) ->
  string = getTranslatedString(stringObject)

Template.registerHelper "getTranslatedStringForLanguage", (stringObject, langCode) ->
  string = getTranslatedString(stringObject, langCode)

Template.registerHelper "supportedLanguages", () ->
  getSupportedLanguages()

################################################################################
# Global Functions
#

# Convert an array of HTML input nodes to the object of strings to be inserted into the database.
@convertNodesToStringObject = (nodes) ->
  stringObj = {}

  for node in nodes
    lang = $(node).data("lang")
    stringObj[lang] = $(node).val()

  stringObj

# Get the correct string translation from an object with all the translations.
# - Default to English if not requesting specific translation and the translation is not available.
@getTranslatedString = (stringObject, langCode) ->
  if langCode?
    string = stringObject[langCode]
  else
    string = stringObject[TAPi18n.getLanguage()] or stringObject["en"]

# Return the blog post but replace the translation string objects with the correct translated string for use by templates.
# Blog post properties that support translations:
# - Body
# - Excerpt
# - Title
@translateBlogPost = (post) ->
  if post and post.body? # Body isn't always present
    post.body = getTranslatedString(post.body)

  post.excerpt = getTranslatedString(post.excerpt)
  post.title = getTranslatedString(post.title)

  post

# Same as translateBlogPost but for an array of posts.
@translateBlogPosts = (posts) ->
  translatedPosts = []

  for post in posts
    translatedPosts.push translateBlogPost(post)

  translatedPosts