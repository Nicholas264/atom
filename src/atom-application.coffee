AtomWindow = require 'atom-window'
ApplicationMenu = require 'application-menu'
BrowserWindow = require 'browser-window'
Menu = require 'menu'
autoUpdater = require 'auto-updater'
app = require 'app'
ipc = require 'ipc'
dialog = require 'dialog'
fs = require 'fs'
path = require 'path'
net = require 'net'
url = require 'url'
{EventEmitter} = require 'events'
_ = require 'underscore'

socketPath = '/tmp/atom.sock'

# Public: The application's singleton class.
#
# It's the entry point into the Atom application and maintains the global state
# of the application. For the most part you won't interact directly with this
# class but you may use one it's provided commands.
#
# ## Commands
#
#  * `application:about` - This opens the about dialog.
#  * `application:show-settings` - This opens the preference pane in the currently
#    focused editor.
#  * `application:quit` - This quits the entire application.
#  * `application:hide` - This hides the entire application.
#  * `application:hide-other-applications` - This hides other applications
#    running on the system.
#  * `application:unhide-other-applications` - This shows other applications
#    that were previously hidden.
#  * `application:new-window` - This opens a new {AtomWindow} with no {Project}
#    path.
#  * `application:new-file` - This creates a new file within the focused window.
#    Note: only one new file may exist within an {AtomWindow} at a time.
#  * `application:open` - Prompts the user for a path to open in a new {AtomWindow}
#  * `application:minimize` - Minimizes the currently focused {AtomWindow}
#  * `application:zoom` - Expands the window to fill the screen or returns it to
#    it's original unzoomed size.
#  * `application:bring-all-windows-to-front` - Brings all {AtomWindow}s to the
#    the front.
module.exports =
class AtomApplication
  _.extend @prototype, EventEmitter.prototype

  # Public: The entry point into the Atom application.
  #
  # Returns nothing.
  @open: (options) ->
    createAtomApplication = -> new AtomApplication(options)

    # FIXME: Sometimes when socketPath doesn't exist, net.connect would strangely
    # take a few seconds to trigger 'error' event, it could be a bug of node
    # or atom-shell, before it's fixed we check the existence of socketPath to
    # speedup startup.
    if not fs.existsSync socketPath
      createAtomApplication()
      return

    client = net.connect {path: socketPath}, ->
      client.write JSON.stringify(options), ->
        client.end()
        app.terminate()

    client.on 'error', createAtomApplication

  windows: null
  applicationMenu: null
  resourcePath: null
  version: null

  constructor: ({@resourcePath, pathsToOpen, urlsToOpen, @version, test, pidToKillWhenClosed, devMode, newWindow}) ->
    global.atomApplication = this

    @pidsToOpenWindows = {}
    @pathsToOpen ?= []
    @windows = []

    @applicationMenu = new ApplicationMenu(@version, devMode)

    @listenForArgumentsFromNewProcess()
    @setupJavaScriptArguments()
    @handleEvents()
    @checkForUpdates()

    if test
      @runSpecs({exitWhenDone: true, @resourcePath})
    else if pathsToOpen.length > 0
      @openPaths({pathsToOpen, pidToKillWhenClosed, newWindow, devMode})
    else if urlsToOpen.length > 0
      @openUrl({urlToOpen, devMode}) for urlToOpen in urlsToOpen
    else
      @openPath({pidToKillWhenClosed, newWindow, devMode}) # Always open a editor window if this is the first instance of Atom.

  # Public: Removes a window from the global window list.
  #
  # window - The relevant {AtomWindow}
  #
  # Returns nothing.
  removeWindow: (window) ->
    @windows.splice @windows.indexOf(window), 1
    @applicationMenu?.enableWindowSpecificItems(false) if @windows.length == 0

  # Public: Adds a window to the global window list.
  #
  # window - The relevant {AtomWindow}
  #
  # Returns nothing.
  addWindow: (window) ->
    @windows.push window
    @applicationMenu?.enableWindowSpecificItems(true)

  # Private: Creates server to listen for additional atom application launches.
  #
  # You can run the atom command multiple times, but after the first launch
  # the other launches will just pass their information to this server and then
  # close immediately.
  #
  # Returns nothing.
  listenForArgumentsFromNewProcess: ->
    fs.unlinkSync socketPath if fs.existsSync(socketPath)
    server = net.createServer (connection) =>
      connection.on 'data', (data) =>
        {pathsToOpen, pidToKillWhenClosed, newWindow} = JSON.parse(data)
        @openPaths({pathsToOpen, pidToKillWhenClosed, newWindow})

    server.listen socketPath
    server.on 'error', (error) -> console.error 'Application server failed', error

  # Private: Configures required javascript environment flags.
  #
  # Returns nothing.
  setupJavaScriptArguments: ->
    app.commandLine.appendSwitch 'js-flags', '--harmony_collections'

  # Private: Determines whether the auto updater should check for updates.
  #
  # If running from a local build, we don't want to update to a released version.
  #
  # Returns nothing.
  checkForUpdates: ->
    versionIsSha = /\w{7}/.test @version

    if versionIsSha
      autoUpdater.setAutomaticallyDownloadsUpdates false
      autoUpdater.setAutomaticallyChecksForUpdates false
    else
      autoUpdater.setAutomaticallyDownloadsUpdates true
      autoUpdater.setAutomaticallyChecksForUpdates true
      autoUpdater.checkForUpdatesInBackground()

  # Private: Registers basic application commands.
  #
  # This should only be called once.
  #
  # Returns nothing.
  handleEvents: ->
    @on 'application:about', -> Menu.sendActionToFirstResponder('orderFrontStandardAboutPanel:')
    @on 'application:run-all-specs', -> @runSpecs(exitWhenDone: false, resourcePath: global.devResourcePath)
    @on 'application:show-settings', -> (@focusedWindow() ? this).openPath("atom://config")
    @on 'application:quit', -> app.quit()
    @on 'application:hide', -> Menu.sendActionToFirstResponder('hide:')
    @on 'application:hide-other-applications', -> Menu.sendActionToFirstResponder('hideOtherApplications:')
    @on 'application:unhide-all-applications', -> Menu.sendActionToFirstResponder('unhideAllApplications:')
    @on 'application:new-window', ->  @openPath()
    @on 'application:new-file', -> (@focusedWindow() ? this).openPath()
    @on 'application:open', -> @promptForPath()
    @on 'application:open-dev', -> @promptForPath(devMode: true)
    @on 'application:minimize', -> Menu.sendActionToFirstResponder('performMiniaturize:')
    @on 'application:zoom', -> Menu.sendActionToFirstResponder('zoom:')
    @on 'application:bring-all-windows-to-front', -> Menu.sendActionToFirstResponder('arrangeInFront:')

    app.on 'will-quit', =>
      fs.unlinkSync socketPath if fs.existsSync(socketPath) # Clean the socket file when quit normally.

    app.on 'open-file', (event, pathToOpen) =>
      event.preventDefault()
      @openPath({pathToOpen})

    app.on 'open-url', (event, urlToOpen) =>
      event.preventDefault()
      @openUrl(urlToOpen)

    autoUpdater.on 'ready-for-update-on-quit', (event, version, quitAndUpdateCallback) =>
      event.preventDefault()
      @applicationMenu.showDownloadUpdateItem(version, quitAndUpdateCallback)

    ipc.on 'open', (processId, routingId, options) =>
      if options?
        if options.pathsToOpen?.length > 0
          @openPaths(options)
        else
          new AtomWindow(options)
      else
        @promptForPath()

    ipc.once 'update-application-menu', (processId, routingId, keystrokesByCommand) =>
      @applicationMenu.update(keystrokesByCommand)

    ipc.on 'run-package-specs', (processId, routingId, packagePath) =>
      @runSpecs({@resourcePath, specPath: packagePath, exitWhenDone: false})

    ipc.on 'command', (processId, routingId, command) =>
      @emit(command)

  # Public: Executes the given command.
  #
  # If it isn't handled globally, delegate to the currently focused window.
  #
  # command - The string representing the command.
  # args    - The optional arguments to pass along.
  #
  # Returns nothing.
  sendCommand: (command, args...) ->
    unless @emit(command, args...)
      @focusedWindow()?.sendCommand(command, args...)

  # Private: Selects the window based on the given path.
  #
  # pathToOpen - The full file path used to select the window.
  #
  # FIXME: This should probably return undefined if no window is found.
  #
  # Returns the {AtomWindow} which is opened to the selected path and the list
  #   of windows otherwise.
  windowForPath: (pathToOpen) ->
    for atomWindow in @windows
      return atomWindow if atomWindow.containsPath(pathToOpen)

  # Public: Finds the currently focused window.
  #
  # Returns the currently focused {AtomWindow} or undefined if none are focused.
  focusedWindow: ->
    _.find @windows, (atomWindow) -> atomWindow.isFocused()

  # Public: Opens multiple paths, in existing windows if possible.
  #
  # options -
  #   pathsToOpen: The array of file paths to open
  #   pidToKillWhenClosed: The integer of the pid to kill
  #   newWindow: Boolean of whether this should be opened in a new window.
  #   devMode: Boolean to control the opened window's dev mode.
  #
  # Returns nothing.
  openPaths: ({pathsToOpen, pidToKillWhenClosed, newWindow, devMode}) ->
    @openPath({pathToOpen, pidToKillWhenClosed, newWindow, devMode}) for pathToOpen in pathsToOpen ? []

  # Public: Opens a single path, in an existing window if possible.
  #
  # options -
  #   pathsToOpen: The array of file paths to open
  #   pidToKillWhenClosed: The integer of the pid to kill
  #   newWindow: Boolean of whether this should be opened in a new window.
  #   devMode: Boolean to control the opened window's dev mode.
  #
  # Returns nothing.
  openPath: ({pathToOpen, pidToKillWhenClosed, newWindow, devMode}={}) ->
    unless devMode
      existingWindow = @windowForPath(pathToOpen) unless pidToKillWhenClosed or newWindow
    if existingWindow
      openedWindow = existingWindow
      openedWindow.openPath(pathToOpen)
    else
      bootstrapScript = 'window-bootstrap'
      if devMode
        resourcePath = global.devResourcePath
      else
        resourcePath = @resourcePath
      openedWindow = new AtomWindow({pathToOpen, bootstrapScript, resourcePath, devMode})

    if pidToKillWhenClosed?
      @pidsToOpenWindows[pidToKillWhenClosed] = openedWindow

    openedWindow.browserWindow.on 'destroyed', =>
      for pid, trackedWindow of @pidsToOpenWindows when trackedWindow is openedWindow
        try
          process.kill(pid)
        catch error
          if error.code isnt 'ESRCH'
            console.log("Killing process #{pid} failed: #{error.code}")
        delete @pidsToOpenWindows[pid]

  # Private: Handles an atom:// url.
  #
  # Currently only supports atom://session/<session-id> urls.
  #
  # options -
  #   urlToOpen: The atom:// url to open.
  #   devMode: Boolean to control the opened window's dev mode.
  openUrl: ({urlToOpen, devMode}) ->
    parsedUrl = url.parse(urlToOpen)
    if parsedUrl.host is 'session'
      sessionId = parsedUrl.path.split('/')[1]
      console.log "Joining session #{sessionId}"
      if sessionId
        bootstrapScript = 'collaboration/lib/bootstrap'
        new AtomWindow({bootstrapScript, @resourcePath, sessionId, devMode})
    else
      console.log "Opening unknown url #{urlToOpen}"

  # Private: Opens up a new {AtomWindow} to run specs within.
  #
  # options -
  #   exitWhenDone: A Boolean that if true, will close the window upon completion.
  #   resourcePath: The path to include specs from.
  #   specPath: The directory to load specs from.
  #
  # Returns nothing.
  runSpecs: ({exitWhenDone, resourcePath, specPath}) ->
    if resourcePath isnt @resourcePath and not fs.existsSync(resourcePath)
      resourcePath = @resourcePath

    bootstrapScript = 'spec-bootstrap'
    isSpec = true
    devMode = true
    new AtomWindow({bootstrapScript, resourcePath, exitWhenDone, isSpec, devMode, specPath})

  # Private: Opens a native dialog to prompt the user for a path.
  #
  # Once paths are selected, they're opened in a new or existing {AtomWindow}s.
  #
  # options -
  #   devMode: A Boolean which controls whether any newly opened windows should
  #            be in dev mode or not.
  #
  # Returns nothing
  promptForPath: ({devMode}={}) ->
    pathsToOpen = dialog.showOpenDialog title: 'Open', properties: ['openFile', 'openDirectory', 'multiSelections', 'createDirectory']
    @openPaths({pathsToOpen, devMode})
