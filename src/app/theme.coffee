fsUtils = require 'fs-utils'

###
# Internal #
###

module.exports =
class Theme
  @stylesheets: null

  @load: (name) ->
    TextMateTheme = require 'text-mate-theme'
    AtomTheme = require 'atom-theme'

    if fsUtils.exists(name)
      path = name
    else
      path = fsUtils.resolve(config.themeDirPaths..., name, ['', '.tmTheme', '.css', 'less'])

    throw new Error("No theme exists named '#{name}'") unless path

    theme =
      if TextMateTheme.testPath(path)
        new TextMateTheme(path)
      else
        new AtomTheme(path)

    theme.load()
    theme

  constructor: (@path) ->
    @stylesheets = {}

  load: ->
    for stylesheetPath, stylesheetContent of @stylesheets
      applyStylesheet(stylesheetPath, stylesheetContent, 'userTheme')

  deactivate: ->
    for stylesheetPath, stylesheetContent of @stylesheets
      removeStylesheet(stylesheetPath)
