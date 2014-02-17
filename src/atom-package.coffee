path = require 'path'

_ = require 'underscore-plus'
CSON = require 'season'
fs = require 'fs-plus'
{Emitter} = require 'emissary'
Q = require 'q'

{$} = require './space-pen-extensions'
Package = require './package'
ScopedProperties = require './scoped-properties'

# Loads and activates a package's main module and resources such as
# stylesheets, keymaps, grammar, editor properties, and menus.
module.exports =
class AtomPackage extends Package
  Emitter.includeInto(this)

  @stylesheetsDir: 'stylesheets'

  keymaps: null
  menus: null
  stylesheets: null
  grammars: null
  scopedProperties: null
  mainModulePath: null
  resolvedMainModulePath: false
  mainModule: null

  constructor: ->
    super
    @reset()

  getType: -> 'atom'

  getStylesheetType: -> 'bundled'

  load: ->
    @measure 'loadTime', =>
      try
        @metadata ?= Package.loadMetadata(@path)

        @loadKeymaps()
        @loadMenus()
        @loadStylesheets()
        @loadGrammars()
        @loadScopedProperties()
        @requireMainModule() unless @metadata.activationEvents?

      catch e
        console.warn "Failed to load package named '#{@name}'", e.stack ? e
    this

  reset: ->
    @stylesheets = []
    @keymaps = []
    @menus = []
    @grammars = []
    @scopedProperties = []

  activate: ->
    return @activationDeferred.promise if @activationDeferred?

    @activationDeferred = Q.defer()
    @measure 'activateTime', =>
      @activateResources()
      if @metadata.activationEvents?
        @subscribeToActivationEvents()
      else
        @activateNow()

    @activationDeferred.promise

  activateNow: ->
    try
      @activateConfig()
      @activateStylesheets()
      if @requireMainModule()
        @mainModule.activate(atom.packages.getPackageState(@name) ? {})
        @mainActivated = true
    catch e
      console.warn "Failed to activate package named '#{@name}'", e.stack

    @activationDeferred.resolve()

  activateConfig: ->
    return if @configActivated

    @requireMainModule()
    if @mainModule?
      atom.config.setDefaults(@name, @mainModule.configDefaults)
      @mainModule.activateConfig?()
    @configActivated = true

  activateStylesheets: ->
    return if @stylesheetsActivated

    type = @getStylesheetType()
    for [stylesheetPath, content] in @stylesheets
      atom.themes.applyStylesheet(stylesheetPath, content, type)
    @stylesheetsActivated = true

  activateResources: ->
    atom.keymap.add(keymapPath, map) for [keymapPath, map] in @keymaps
    atom.contextMenu.add(menuPath, map['context-menu']) for [menuPath, map] in @menus
    atom.menu.add(map.menu) for [menuPath, map] in @menus when map.menu

    grammar.activate() for grammar in @grammars
    @grammarsActivated = true

    scopedProperties.activate() for scopedProperties in @scopedProperties
    @scopedPropertiesActivated = true

  loadKeymaps: ->
    @keymaps = @getKeymapPaths().map (keymapPath) -> [keymapPath, CSON.readFileSync(keymapPath)]

  loadMenus: ->
    @menus = @getMenuPaths().map (menuPath) -> [menuPath, CSON.readFileSync(menuPath)]

  getKeymapPaths: ->
    keymapsDirPath = path.join(@path, 'keymaps')
    if @metadata.keymaps
      @metadata.keymaps.map (name) -> fs.resolve(keymapsDirPath, name, ['json', 'cson', ''])
    else
      fs.listSync(keymapsDirPath, ['cson', 'json'])

  getMenuPaths: ->
    menusDirPath = path.join(@path, 'menus')
    if @metadata.menus
      @metadata.menus.map (name) -> fs.resolve(menusDirPath, name, ['json', 'cson', ''])
    else
      fs.listSync(menusDirPath, ['cson', 'json'])

  loadStylesheets: ->
    @stylesheets = @getStylesheetPaths().map (stylesheetPath) ->
      [stylesheetPath, atom.themes.loadStylesheet(stylesheetPath)]

  getStylesheetsPath: ->
    path.join(@path, @constructor.stylesheetsDir)

  getStylesheetPaths: ->
    stylesheetDirPath = @getStylesheetsPath()

    if @metadata.stylesheetMain
      [fs.resolve(@path, @metadata.stylesheetMain)]
    else if @metadata.stylesheets
      @metadata.stylesheets.map (name) -> fs.resolve(stylesheetDirPath, name, ['css', 'less', ''])
    else if indexStylesheet = fs.resolve(@path, 'index', ['css', 'less'])
      [indexStylesheet]
    else
      fs.listSync(stylesheetDirPath, ['css', 'less'])

  loadGrammars: ->
    @grammars = []

    loadGrammar = (grammarPath) =>
      atom.syntax.readGrammar grammarPath, (error, grammar) =>
        if error?
          console.warn("Failed to load grammar: #{grammarPath}", error.stack ? error)
        else
          @grammars.push(grammar)
          grammar.activate() if @grammarsActivated

    grammarsDirPath = path.join(@path, 'grammars')
    fs.list grammarsDirPath, ['.json', '.cson'], (error, grammarPaths=[]) ->
      loadGrammar(grammarPath) for grammarPath in grammarPaths

  loadScopedProperties: ->
    @scopedProperties = []

    loadScopedPropertiesFile = (scopedPropertiesPath) =>
      ScopedProperties.load scopedPropertiesPath, (error, scopedProperties) =>
        if error?
          console.warn("Failed to load scoped properties: #{scopedPropertiesPath}", error.stack ? error)
        else
          @scopedProperties.push(scopedProperties)
          scopedProperties.activate() if @scopedPropertiesActivated

    scopedPropertiesDirPath = path.join(@path, 'scoped-properties')
    fs.list scopedPropertiesDirPath, ['.json', '.cson'], (error, scopedPropertiesPaths=[]) ->
      for scopedPropertiesPath in scopedPropertiesPaths
        loadScopedPropertiesFile(scopedPropertiesPath)

  serialize: ->
    if @mainActivated
      try
        @mainModule?.serialize?()
      catch e
        console.error "Error serializing package '#{@name}'", e.stack

  deactivate: ->
    @activationDeferred?.reject()
    @activationDeferred = null
    @unsubscribeFromActivationEvents()
    @deactivateResources()
    @deactivateConfig()
    @mainModule?.deactivate?() if @mainActivated
    @emit('deactivated')

  deactivateConfig: ->
    @mainModule?.deactivateConfig?()
    @configActivated = false

  deactivateResources: ->
    grammar.deactivate() for grammar in @grammars
    scopedProperties.deactivate() for scopedProperties in @scopedProperties
    atom.keymap.remove(keymapPath) for [keymapPath] in @keymaps
    atom.themes.removeStylesheet(stylesheetPath) for [stylesheetPath] in @stylesheets
    @stylesheetsActivated = false
    @grammarsActivated = false
    @scopedPropertiesActivated = false

  reloadStylesheets: ->
    oldSheets = _.clone(@stylesheets)
    @loadStylesheets()
    atom.themes.removeStylesheet(stylesheetPath) for [stylesheetPath] in oldSheets
    @reloadStylesheet(stylesheetPath, content) for [stylesheetPath, content] in @stylesheets

  reloadStylesheet: (stylesheetPath, content) ->
    atom.themes.applyStylesheet(stylesheetPath, content, @getStylesheetType())

  requireMainModule: ->
    return @mainModule if @mainModule?
    mainModulePath = @getMainModulePath()
    @mainModule = require(mainModulePath) if fs.isFileSync(mainModulePath)

  getMainModulePath: ->
    return @mainModulePath if @resolvedMainModulePath
    @resolvedMainModulePath = true
    mainModulePath =
      if @metadata.main
        path.join(@path, @metadata.main)
      else
        path.join(@path, 'index')
    @mainModulePath = fs.resolveExtension(mainModulePath, ["", _.keys(require.extensions)...])

  subscribeToActivationEvents: ->
    return unless @metadata.activationEvents?
    if _.isArray(@metadata.activationEvents)
      atom.workspaceView.command(event, @handleActivationEvent) for event in @metadata.activationEvents
    else if _.isString(@metadata.activationEvents)
      atom.workspaceView.command(@metadata.activationEvents, @handleActivationEvent)
    else
      atom.workspaceView.command(event, selector, @handleActivationEvent) for event, selector of @metadata.activationEvents

  handleActivationEvent: (event) =>
    bubblePathEventHandlers = @disableEventHandlersOnBubblePath(event)
    @activateNow()
    $(event.target).trigger(event)
    @restoreEventHandlersOnBubblePath(bubblePathEventHandlers)
    @unsubscribeFromActivationEvents()

  unsubscribeFromActivationEvents: ->
    return unless atom.workspaceView?

    if _.isArray(@metadata.activationEvents)
      atom.workspaceView.off(event, @handleActivationEvent) for event in @metadata.activationEvents
    else if _.isString(@metadata.activationEvents)
      atom.workspaceView.off(@metadata.activationEvents, @handleActivationEvent)
    else
      atom.workspaceView.off(event, selector, @handleActivationEvent) for event, selector of @metadata.activationEvents

  disableEventHandlersOnBubblePath: (event) ->
    bubblePathEventHandlers = []
    disabledHandler = ->
    element = $(event.target)
    while element.length
      if eventHandlers = element.handlers()?[event.type]
        for eventHandler in eventHandlers
          eventHandler.disabledHandler = eventHandler.handler
          eventHandler.handler = disabledHandler
          bubblePathEventHandlers.push(eventHandler)
      element = element.parent()
    bubblePathEventHandlers

  restoreEventHandlersOnBubblePath: (eventHandlers) ->
    for eventHandler in eventHandlers
      eventHandler.handler = eventHandler.disabledHandler
      delete eventHandler.disabledHandler
