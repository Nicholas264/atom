path = require 'path'

_ = require 'underscore-plus'
async = require 'async'
CSON = require 'season'
fs = require 'fs-plus'
{Emitter} = require 'emissary'
Q = require 'q'

$ = null # Defer require in case this is in the window-less browser process
ScopedProperties = require './scoped-properties'

# Loads and activates a package's main module and resources such as
# stylesheets, keymaps, grammar, editor properties, and menus.
module.exports =
class Package
  Emitter.includeInto(this)

  @stylesheetsDir: 'stylesheets'

  @loadMetadata: (packagePath, ignoreErrors=false) ->
    if metadataPath = CSON.resolve(path.join(packagePath, 'package'))
      try
        metadata = CSON.readFileSync(metadataPath)
      catch error
        throw error unless ignoreErrors
    metadata ?= {}
    metadata.name = path.basename(packagePath)
    metadata

  keymaps: null
  menus: null
  stylesheets: null
  grammars: null
  scopedProperties: null
  mainModulePath: null
  resolvedMainModulePath: false
  mainModule: null

  constructor: (@path, @metadata) ->
    @metadata ?= Package.loadMetadata(@path)
    @name = @metadata?.name ? path.basename(@path)
    @reset()

    atom.syntax.on 'request-grammar-preload', ({packageName, scopeName}={}) =>
      @loadGrammarsSync() if packageName == @name

  enable: ->
    atom.config.removeAtKeyPath('core.disabledPackages', @name)

  disable: ->
    atom.config.pushAtKeyPath('core.disabledPackages', @name)

  isTheme: ->
    @metadata?.theme?

  measure: (key, fn) ->
    startTime = Date.now()
    value = fn()
    @[key] = Date.now() - startTime
    value

  getType: -> 'atom'

  getStylesheetType: -> 'bundled'

  load: ->
    @measure 'loadTime', =>
      try
        @loadKeymaps()
        @loadMenus()
        @loadStylesheets()
        @scopedPropertiesPromise = @loadScopedProperties()
        @requireMainModule() unless @hasActivationEvents()

      catch error
        console.warn "Failed to load package named '#{@name}'", error.stack ? error
    this

  reset: ->
    @stylesheets = []
    @keymaps = []
    @menus = []
    @grammars = []
    @scopedProperties = []

  activate: ->
    @grammarsPromise = @loadGrammars()

    unless @activationDeferred?
      @activationDeferred = Q.defer()
      @measure 'activateTime', =>
        @activateResources()
        if @hasActivationEvents()
          @subscribeToActivationEvents()
        else
          @activateNow()

    Q.all([@grammarsPromise, @scopedPropertiesPromise, @activationDeferred.promise])

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
    atom.keymaps.add(keymapPath, map) for [keymapPath, map] in @keymaps
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

  loadGrammarsSync: ->
    return if @grammarsLoaded

    grammarsDirPath = path.join(@path, 'grammars')
    grammarPaths = fs.listSync(grammarsDirPath, ['json', 'cson'])
    for grammarPath in grammarPaths
      console.log 'load sync', grammarPath
      try
        grammar = atom.syntax.readGrammarSync(grammarPath)
        @grammars.push(grammar)
        grammar.activate()
      catch
        console.warn("Failed to load grammar: #{grammarPath}", error.stack ? error)

    @grammarsLoaded = true

  loadGrammars: ->
    return if @grammarsLoaded

    loadGrammar = (grammarPath, callback) =>
      atom.syntax.readGrammar grammarPath, (error, grammar) =>
        if error?
          console.warn("Failed to load grammar: #{grammarPath}", error.stack ? error)
        else
          @grammars.push(grammar)
          grammar.activate() if @grammarsActivated
        callback()

    deferred = Q.defer()
    grammarsDirPath = path.join(@path, 'grammars')
    fs.list grammarsDirPath, ['json', 'cson'], (error, grammarPaths=[]) ->
      async.each grammarPaths, loadGrammar, -> deferred.resolve()
    deferred.promise

  loadScopedProperties: ->
    @scopedProperties = []

    loadScopedPropertiesFile = (scopedPropertiesPath, callback) =>
      ScopedProperties.load scopedPropertiesPath, (error, scopedProperties) =>
        if error?
          console.warn("Failed to load scoped properties: #{scopedPropertiesPath}", error.stack ? error)
        else
          @scopedProperties.push(scopedProperties)
          scopedProperties.activate() if @scopedPropertiesActivated
        callback()

    deferred = Q.defer()
    scopedPropertiesDirPath = path.join(@path, 'scoped-properties')
    fs.list scopedPropertiesDirPath, ['json', 'cson'], (error, scopedPropertiesPaths=[]) ->
      async.each scopedPropertiesPaths, loadScopedPropertiesFile, -> deferred.resolve()
    deferred.promise

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
    atom.keymaps.remove(keymapPath) for [keymapPath] in @keymaps
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

  hasActivationEvents: ->
    if _.isArray(@metadata.activationEvents)
      return @metadata.activationEvents.some (activationEvent) ->
        activationEvent?.length > 0
    else if _.isString(@metadata.activationEvents)
      return @metadata.activationEvents.length > 0
    else if _.isObject(@metadata.activationEvents)
      for event, selector of @metadata.activationEvents
        return true if event.length > 0 and selector.length > 0

    false

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
    $ ?= require('./space-pen-extensions').$
    $(event.target).trigger(event)
    @restoreEventHandlersOnBubblePath(bubblePathEventHandlers)
    @unsubscribeFromActivationEvents()
    false

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
    $ ?= require('./space-pen-extensions').$
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
