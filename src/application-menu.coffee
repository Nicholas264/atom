ipc = require 'ipc'
Menu = require 'menu'

module.exports =
class ApplicationMenu
  keyBindingsByCommand: null
  version: null
  devMode: null
  menu: null

  constructor: (@devMode, @version) ->
    @createDefaultMenu()

  update: (@keyBindingsByCommand) ->
    menuTemplate = @getMenuTemplate()
    @parseMenuTemplate(menuTemplate)
    @menu = Menu.buildFromTemplate(menuTemplate)
    Menu.setApplicationMenu(@menu)
    @enableWindowMenuItems(true)

  allMenuItems: (menu=@menu) ->
    menuItems = []
    for index, item of menu.items or {}
      menuItems.push(item)
      menuItems = menuItems.concat(@allMenuItems(item.submenu)) if item.submenu

    menuItems

  enableWindowMenuItems: (enable) ->
    for menuItem in @allMenuItems()
      menuItem.enabled = enable if menuItem.metadata?['windowMenuItem']

  parseMenuTemplate: (menuTemplate) ->
    menuTemplate.forEach (menuItem) =>
      menuItem.metadata = {}
      if menuItem.command
        menuItem.accelerator = @acceleratorForCommand(menuItem.command)
        menuItem.click = => global.atomApplication.sendCommand(menuItem.command)
        menuItem.metadata['windowMenuItem'] = true unless /^application:/.test(menuItem.command)
      @parseMenuTemplate(menuItem.submenu) if menuItem.submenu

  showDownloadUpdateItem: (version, quitAndUpdateCallback) ->
    downloadUpdateItem = _.find @allMenuItems(), (item) -> item.label == 'Install update'
    if downloadUpdateItem
      downloadUpdateItem.visible = true
      downloadUpdateItem.click = quitAndUpdateCallback

  createDefaultMenu: ->
    @menu = Menu.buildFromTemplate [
      label: "Atom"
      submenu: [
          { label: 'Reload', accelerator: 'Command+R', click: -> @focusedWindow()?.reload() }
          { label: 'Close Window', accelerator: 'Command+Shift+W', click: -> @focusedWindow()?.close() }
          { label: 'Toggle Dev Tools', accelerator: 'Command+Alt+I', click: -> @focusedWindow()?.toggleDevTools() }
          { label: 'Quit', accelerator: 'Command+Q', click: -> app.quit }
      ]
    ]

    Menu.setApplicationMenu @menu

  getMenuTemplate: ->
    atomMenu =
      label: 'Atom'
      submenu: [
        { label: 'About Atom', command: 'application:about' }
        { label: "Version #{@version}", enabled: false }
        { label: "Install update", command: 'application:install-update', visible: false }
        { type: 'separator' }
        { label: 'Preferences...', command: 'application:show-settings' }
        { label: 'Hide Atom', command: 'application:hide' }
        { label: 'Hide Others', command: 'application:hide-other-applications' }
        { label: 'Show All', command: 'application:unhide-all-applications' }
        { type: 'separator' }
        { label: 'Run Specs', command: 'application:run-specs' }
        { type: 'separator' }
        { label: 'Quit', command: 'application:quit' }
      ]

    fileMenu =
      label: 'File'
      submenu: [
        { label: 'New Window', command: 'application:new-window' }
        { label: 'New File', command: 'application:new-file' }
        { type: 'separator' }
        { label: 'Open...', command: 'application:open' }
        { label: 'Open In Dev Mode...', command: 'application:open-dev' }
        { type: 'separator' }
        { label: 'Close Window', command: 'window:close' }
      ]

    editMenu =
      label: 'Edit'
      submenu: [
        { label: 'Undo', command: 'core:undo' }
        { label: 'Redo', command: 'core:redo' }
        { type: 'separator' }
        { label: 'Cut', command: 'core:cut' }
        { label: 'Copy', command: 'core:copy' }
        { label: 'Paste', command: 'core:paste' }
        { label: 'Select All', command: 'core:select-all' }
      ]

    viewMenu =
      label: 'View'
      submenu: [
        { label: 'Reload', command: 'window:reload' }
        { label: 'Toggle Full Screen', command: 'window:toggle-full-screen' }
        { label: 'Toggle Developer Tools', command: 'window:toggle-dev-tools' }
      ]

    windowMenu =
      label: 'Window'
      submenu: [
        { label: 'Minimize', command: 'application:minimize' }
        { label: 'Zoom', command: 'application:zoom' }
        { type: 'separator' }
        { label: 'Bring All to Front', command: 'application:bring-all-windows-to-front' }
      ]

    menu = [atomMenu, fileMenu, editMenu, viewMenu, windowMenu]
    if @devMode
      menu.push
        label: '\uD83D\uDC80' # Skull emoji
        submenu: [ { label: 'In Development Mode', enabled: false } ]

    menu

  acceleratorForCommand: (command) ->
    keyBinding = @keyBindingsByCommand[command]?[0]
    return null unless keyBinding

    modifiers = keyBinding.split('-')
    key = modifiers.pop()

    modifiers.push("Shift") if key != key.toLowerCase()
    modifiers = modifiers.map (modifier) ->
      modifier.replace(/shift/ig, "Shift")
              .replace(/meta/ig, "Command")
              .replace(/ctrl/ig, "MacCtrl")
              .replace(/alt/ig, "Alt")

    keys = modifiers.concat([key.toUpperCase()])
    keys.join("+")
