path = require 'path'

_ = require 'underscore-plus'
{Emitter} = require 'emissary'
fs = require 'fs-plus'

Package = require './package'
AtomPackage = require './atom-package'
{$} = require './space-pen-extensions'


# Private: Handles discovering and loading available themes.
###
Themes are a subset of packages
###
module.exports =
class ThemeManager
  Emitter.includeInto(this)

  constructor: ({@packageManager, @resourcePath, @configDirPath}) ->
    @lessCache = null
    @packageManager.registerPackageActivator(this, ['theme'])

  # Internal-only:
  getAvailableNames: ->
    # TODO: Maybe should change to list all the available themes out there?
    @getLoadedNames()

  getLoadedNames: ->
    theme.name for theme in @getLoadedThemes()

  # Internal-only:
  getActiveNames: ->
    theme.name for theme in @getActiveThemes()

  # Internal-only:
  getActiveThemes: ->
    pack for pack in @packageManager.getActivePackages() when pack.isTheme()

  # Internal-only:
  getLoadedThemes: ->
    pack for pack in @packageManager.getLoadedPackages() when pack.isTheme()

  # Internal-only: adhere to the PackageActivator interface
  activatePackages: (themePackages) -> @activateThemes()

  # Internal-only:
  activateThemes: ->
    # atom.config.observe runs the callback once, then on subsequent changes.
    atom.config.observe 'core.themes', (themeNames) =>
      @deactivateThemes()
      themeNames = [themeNames] unless _.isArray(themeNames)

      # Reverse so the first (top) theme is loaded after the others. We want
      # the first/top theme to override later themes in the stack.
      themeNames = _.clone(themeNames).reverse()

      @packageManager.activatePackage(themeName) for themeName in themeNames
      @loadUserStylesheet()
      @reloadBaseStylesheets()
      @emit('reloaded')

  # Internal-only:
  deactivateThemes: ->
    @removeStylesheet(@userStylesheetPath) if @userStylesheetPath?
    @packageManager.deactivatePackage(pack.name) for pack in @getActiveThemes()
    null

  # Public: Set the list of enabled themes.
  #
  # * enabledThemeNames: An {Array} of {String} theme names.
  setEnabledThemes: (enabledThemeNames) ->
    atom.config.set('core.themes', enabledThemeNames)

  # Public:
  getImportPaths: ->
    activeThemes = @getActiveThemes()
    if activeThemes.length > 0
      themePaths = (theme.getStylesheetsPath() for theme in activeThemes when theme)
    else
      themePaths = []
      for themeName in atom.config.get('core.themes') ? []
        if themePath = @packageManager.resolvePackagePath(themeName)
          themePaths.push(path.join(themePath, AtomPackage.stylesheetsDir))

    themePath for themePath in themePaths when fs.isDirectorySync(themePath)

  # Public:
  getUserStylesheetPath: ->
    stylesheetPath = fs.resolve(path.join(@configDirPath, 'user'), ['css', 'less'])
    if fs.isFileSync(stylesheetPath)
      stylesheetPath
    else
      null

  # Private:
  loadUserStylesheet: ->
    if userStylesheetPath = @getUserStylesheetPath()
      @userStylesheetPath = userStylesheetPath
      userStylesheetContents = @loadStylesheet(userStylesheetPath)
      @applyStylesheet(userStylesheetPath, userStylesheetContents, 'userTheme')

  # Internal-only:
  loadBaseStylesheets: ->
    @requireStylesheet('bootstrap/less/bootstrap')
    @reloadBaseStylesheets()

  # Internal-only:
  reloadBaseStylesheets: ->
    @requireStylesheet('../static/atom')
    if nativeStylesheetPath = fs.resolveOnLoadPath(process.platform, ['css', 'less'])
      @requireStylesheet(nativeStylesheetPath)

  # Internal-only:
  stylesheetElementForId: (id, htmlElement) ->
    htmlElement.find("""head style[id="#{id}"]""")

  # Internal-only:
  resolveStylesheet: (stylesheetPath) ->
    if path.extname(stylesheetPath).length > 0
      fs.resolveOnLoadPath(stylesheetPath)
    else
      fs.resolveOnLoadPath(stylesheetPath, ['css', 'less'])

  # Public: resolves and applies the stylesheet specified by the path.
  #
  # * stylesheetPath: String. Can be an absolute path or the name of a CSS or
  #   LESS file in the stylesheets path.
  #
  # Returns the absolute path to the stylesheet
  requireStylesheet: (stylesheetPath, ttype = 'bundled', htmlElement) ->
    if fullPath = @resolveStylesheet(stylesheetPath)
      content = @loadStylesheet(fullPath)
      @applyStylesheet(fullPath, content, ttype = 'bundled', htmlElement)
    else
      throw new Error("Could not find a file at path '#{stylesheetPath}'")

    fullPath

  # Internal-only:
  loadStylesheet: (stylesheetPath) ->
    if path.extname(stylesheetPath) is '.less'
      @loadLessStylesheet(stylesheetPath)
    else
      fs.readFileSync(stylesheetPath, 'utf8')

  # Internal-only:
  loadLessStylesheet: (lessStylesheetPath) ->
    unless lessCache?
      LessCompileCache = require './less-compile-cache'
      @lessCache = new LessCompileCache({@resourcePath})

    try
      @lessCache.read(lessStylesheetPath)
    catch e
      console.error """
        Error compiling less stylesheet: #{lessStylesheetPath}
        Line number: #{e.line}
        #{e.message}
      """

  # Internal-only:
  stringToId: (string) ->
    string.replace(/\\/g, '/')

  # Internal-only:
  removeStylesheet: (stylesheetPath) ->
    unless fullPath = @resolveStylesheet(stylesheetPath)
      throw new Error("Could not find a file at path '#{stylesheetPath}'")
    @stylesheetElementForId(@stringToId(fullPath)).remove()

  # Internal-only:
  applyStylesheet: (path, text, ttype = 'bundled', htmlElement=$('html')) ->
    styleElement = @stylesheetElementForId(@stringToId(path), htmlElement)
    if styleElement.length
      styleElement.text(text)
    else
      if htmlElement.find("head style.#{ttype}").length
        htmlElement.find("head style.#{ttype}:last").after "<style class='#{ttype}' id='#{@stringToId(path)}'>#{text}</style>"
      else
        htmlElement.find("head").append "<style class='#{ttype}' id='#{@stringToId(path)}'>#{text}</style>"
