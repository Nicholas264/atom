path = require 'path'
{Disposable, CompositeDisposable} = require 'event-kit'
ipc = require 'ipc'
shell = require 'shell'
fs = require 'fs-plus'
listen = require './delegated-listener'

# Handles low-level events related to the window.
module.exports =
class WindowEventHandler
  constructor: ({@atomEnvironment}) ->
    @reloadRequested = false
    @subscriptions = new CompositeDisposable

    @addEventListener(window, 'focus', @handleWindowFocus)
    @addEventListener(window, 'blur', @handleWindowBlur)
    @addEventListener(window, 'beforeunload', @handleWindowBeforeunload)
    @addEventListener(window, 'unload', @handleWindowUnload)

    @addEventListener(document, 'keydown', @handleDocumentKeydown)
    @addEventListener(document, 'drop', @handleDocumentDrop)
    @addEventListener(document, 'dragover', @handleDocumentDragover)
    @addEventListener(document, 'contextmenu', @handleDocumentContextmenu)
    @subscriptions.add listen(document, 'click', 'a', @handleLinkClick)
    @subscriptions.add listen(document, 'submit', 'form', @handleFormSubmit)

    @subscriptions.add @atomEnvironment.commands.add window,
      'window:toggle-full-screen': @handleWindowToggleFullScreen
      'window:close': @handleWindowClose
      'window:reload': @handleWindowReload
      'window:toggle-dev-tools': @handleWindowToggleDevTools

    if process.platform in ['win32', 'linux']
      @subscriptions.add @atomEnvironment.commands.add window,
        'window:toggle-menu-bar': @handleWindowToggleMenuBar

    @subscriptions.add @atomEnvironment.commands.add document,
      'core:focus-next': @handleFocusNext
      'core:focus-previous': @handleFocusPrevious

    @handleNativeKeybindings()

  # Wire commands that should be handled by Chromium for elements with the
  # `.native-key-bindings` class.
  handleNativeKeybindings: ->
    bindCommandToAction = (command, action) =>
      @addEventListener document, command, (event) =>
        if event.target.webkitMatchesSelector('.native-key-bindings')
          @atomEnvironment.getCurrentWindow().webContents[action]()

    bindCommandToAction('core:copy', 'copy')
    bindCommandToAction('core:paste', 'paste')
    bindCommandToAction('core:undo', 'undo')
    bindCommandToAction('core:redo', 'redo')
    bindCommandToAction('core:select-all', 'selectAll')
    bindCommandToAction('core:cut', 'cut')

  unsubscribe: ->
    @subscriptions.dispose()

  on: (target, eventName, handler) ->
    target.on(eventName, handler)
    @subscriptions.add(new Disposable ->
      target.removeListener(eventName, handler)
    )

  addEventListener: (target, eventName, handler) ->
    target.addEventListener(eventName, handler)
    @subscriptions.add(new Disposable(-> target.removeEventListener(eventName, handler)))

  handleDocumentKeydown: (event) =>
    @atomEnvironment.keymaps.handleKeyboardEvent(event)
    event.stopImmediatePropagation()

  handleDrop: (event) ->
    event.preventDefault()
    event.stopPropagation()

  handleDragover: (event) ->
    event.preventDefault()
    event.stopPropagation()
    event.dataTransfer.dropEffect = 'none'

  eachTabIndexedElement: (callback) ->
    for element in document.querySelectorAll('[tabindex]')
      continue if element.disabled
      continue unless element.tabIndex >= 0
      callback(element, element.tabIndex)
    return

  handleFocusNext: =>
    focusedTabIndex = document.activeElement.tabIndex ? -Infinity

    nextElement = null
    nextTabIndex = Infinity
    lowestElement = null
    lowestTabIndex = Infinity
    @eachTabIndexedElement (element, tabIndex) ->
      if tabIndex < lowestTabIndex
        lowestTabIndex = tabIndex
        lowestElement = element

      if focusedTabIndex < tabIndex < nextTabIndex
        nextTabIndex = tabIndex
        nextElement = element

    if nextElement?
      nextElement.focus()
    else if lowestElement?
      lowestElement.focus()

  handleFocusPrevious: =>
    focusedTabIndex = document.activeElement.tabIndex ? Infinity

    previousElement = null
    previousTabIndex = -Infinity
    highestElement = null
    highestTabIndex = -Infinity
    @eachTabIndexedElement (element, tabIndex) ->
      if tabIndex > highestTabIndex
        highestTabIndex = tabIndex
        highestElement = element

      if focusedTabIndex > tabIndex > previousTabIndex
        previousTabIndex = tabIndex
        previousElement = element

    if previousElement?
      previousElement.focus()
    else if highestElement?
      highestElement.focus()

  handleWindowFocus: ->
    document.body.classList.remove('is-blurred')

  handleWindowBlur: =>
    document.body.classList.add('is-blurred')
    @atomEnvironment.storeDefaultWindowDimensions()

  handleWindowBeforeunload: =>
    confirmed = @atomEnvironment.workspace?.confirmClose(windowCloseRequested: true)
    @atomEnvironment.hide() if confirmed and not @reloadRequested and @atomEnvironment.getCurrentWindow().isWebViewFocused()
    @reloadRequested = false

    @atomEnvironment.storeDefaultWindowDimensions()
    @atomEnvironment.storeWindowDimensions()
    if confirmed
      @atomEnvironment.unloadEditorWindow()
    else
      ipc.send('cancel-window-close')

    confirmed

  handleWindowUnload: =>
    @atomEnvironment.destroy()

  handleWindowToggleFullScreen: =>
    @atomEnvironment.toggleFullScreen()

  handleWindowClose: =>
    @atomEnvironment.close()

  handleWindowReload: =>
    @reloadRequested = true
    @atomEnvironment.reload()

  handleWindowToggleDevTools: =>
    @atomEnvironment.toggleDevTools()

  handleWindowToggleMenuBar: =>
    @atomEnvironment.config.set('core.autoHideMenuBar', not @atomEnvironment.config.get('core.autoHideMenuBar'))

    if @atomEnvironment.config.get('core.autoHideMenuBar')
      detail = "To toggle, press the Alt key or execute the window:toggle-menu-bar command"
      @atomEnvironment.notifications.addInfo('Menu bar hidden', {detail})

  handleLinkClick: (event) ->
    event.preventDefault()
    location = event.currentTarget?.getAttribute('href')
    if location and location[0] isnt '#' and /^https?:\/\//.test(location)
      shell.openExternal(location)

  handleFormSubmit: (event) ->
    # Prevent form submits from changing the current window's URL
    event.preventDefault()

  handleDocumentContextmenu: (event) =>
    event.preventDefault()
    @atomEnvironment.contextMenu.showForEvent(event)
