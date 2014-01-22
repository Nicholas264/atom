ipc = require 'ipc'
path = require 'path'
Q = require 'q'
_ = require 'underscore-plus'
Delegator = require 'delegato'
{$, $$, View} = require './space-pen-extensions'
fs = require 'fs-plus'
Workspace = require './workspace'
CommandInstaller = require './command-installer'
EditorView = require './editor-view'
PaneView = require './pane-view'
PaneColumnView = require './pane-column-view'
PaneRowView = require './pane-row-view'
PaneContainerView = require './pane-container-view'
Editor = require './editor'

# Public: The container for the entire Atom application.
#
# ## Commands
#
#  * `application:about` - Opens the about dialog.
#  * `application:show-settings` - Opens the preference pane in the currently
#    focused editor.
#  * `application:quit` - Quits the entire application.
#  * `application:hide` - Hides the entire application.
#  * `application:hide-other-applications` - Hides other applications
#    running on the system.
#  * `application:unhide-other-applications` - Shows other applications
#    that were previously hidden.
#  * `application:new-window` - Opens a new {AtomWindow} with no {Project}
#    path.
#  * `application:new-file` - Creates a new file within the focused window.
#    Note: only one new file may exist within an {AtomWindow} at a time.
#  * `application:open` - Prompts the user for a path to open in a new {AtomWindow}
#  * `application:minimize` - Minimizes the currently focused {AtomWindow}
#  * `application:zoom` - Expands the window to fill the screen or returns it to
#    it's original unzoomed size.
#  * `application:bring-all-windows-to-front` - Brings all {AtomWindow}s to the
#    the front.
#
# ## Requiring in package specs
#
# ```coffee
#   {WorkspaceView} = require 'atom'
# ```
module.exports =
class WorkspaceView extends View
  Delegator.includeInto(this)

  @delegatesProperty 'fullScreen', 'destroyedItemUris', toProperty: 'model'
  @delegatesMethods 'open', 'openSync', 'openSingletonSync', 'reopenItemSync',
    'saveActivePaneItem', 'saveActivePaneItemAs', 'saveAll', 'destroyActivePaneItem',
    'destroyActivePane', toProperty: 'model'

  @version: 4

  @configDefaults:
    ignoredNames: [".git", ".svn", ".DS_Store"]
    excludeVcsIgnoredPaths: true
    disabledPackages: []
    themes: ['atom-dark-ui', 'atom-dark-syntax']
    projectHome: path.join(fs.getHomeDirectory(), 'github')
    audioBeep: true
    destroyEmptyPanes: false

  # Private:
  @content: ->
    @div class: 'workspace', tabindex: -1, =>
      @div class: 'horizontal', outlet: 'horizontal', =>
        @div class: 'vertical', outlet: 'vertical', =>
          @div class: 'panes', outlet: 'panes'

  # Private:
  initialize: (@model) ->
    @model ?= new Workspace

    panes = new PaneContainerView(@model.paneContainer)
    @panes.replaceWith(panes)
    @panes = panes

    @subscribe @model, 'uri-opened', => @trigger 'uri-opened'

    @updateTitle()

    @on 'focus', (e) => @handleFocus(e)
    @subscribe $(window), 'focus', (e) =>
      @handleFocus(e) if document.activeElement is document.body

    atom.project.on 'path-changed', => @updateTitle()
    @on 'pane-container:active-pane-item-changed', => @updateTitle()
    @on 'pane:active-item-title-changed', '.active.pane', => @updateTitle()

    @command 'application:about', -> ipc.sendChannel('command', 'application:about')
    @command 'application:run-all-specs', -> ipc.sendChannel('command', 'application:run-all-specs')
    @command 'application:run-benchmarks', -> ipc.sendChannel('command', 'application:run-benchmarks')
    @command 'application:show-settings', -> ipc.sendChannel('command', 'application:show-settings')
    @command 'application:quit', -> ipc.sendChannel('command', 'application:quit')
    @command 'application:hide', -> ipc.sendChannel('command', 'application:hide')
    @command 'application:hide-other-applications', -> ipc.sendChannel('command', 'application:hide-other-applications')
    @command 'application:unhide-all-applications', -> ipc.sendChannel('command', 'application:unhide-all-applications')
    @command 'application:new-window', -> ipc.sendChannel('command', 'application:new-window')
    @command 'application:new-file', -> ipc.sendChannel('command', 'application:new-file')
    @command 'application:open', -> ipc.sendChannel('command', 'application:open')
    @command 'application:open-dev', -> ipc.sendChannel('command', 'application:open-dev')
    @command 'application:minimize', -> ipc.sendChannel('command', 'application:minimize')
    @command 'application:zoom', -> ipc.sendChannel('command', 'application:zoom')
    @command 'application:bring-all-windows-to-front', -> ipc.sendChannel('command', 'application:bring-all-windows-to-front')
    @command 'application:open-your-config', -> ipc.sendChannel('command', 'application:open-your-config')
    @command 'application:open-your-keymap', -> ipc.sendChannel('command', 'application:open-your-keymap')
    @command 'application:open-your-stylesheet', -> ipc.sendChannel('command', 'application:open-your-stylesheet')

    @command 'window:install-shell-commands', => @installShellCommands()

    @command 'window:run-package-specs', => ipc.sendChannel('run-package-specs', path.join(atom.project.getPath(), 'spec'))
    @command 'window:increase-font-size', =>
      atom.config.set("editor.fontSize", atom.config.get("editor.fontSize") + 1)

    @command 'window:decrease-font-size', =>
      fontSize = atom.config.get "editor.fontSize"
      atom.config.set("editor.fontSize", fontSize - 1) if fontSize > 1

    @command 'window:focus-next-pane', => @focusNextPane()
    @command 'window:focus-previous-pane', => @focusPreviousPane()
    @command 'window:save-all', => @saveAll()
    @command 'window:toggle-invisibles', =>
      atom.config.toggle("editor.showInvisibles")

    @command 'window:toggle-auto-indent', =>
      atom.config.toggle("editor.autoIndent")

    @command 'pane:reopen-closed-item', => @reopenItemSync()

    @command 'core:close', => if @getActivePaneItem()? then @destroyActivePaneItem() else @destroyActivePane()
    @command 'core:save', => @saveActivePaneItem()
    @command 'core:save-as', => @saveActivePaneItemAs()

  installShellCommands: ->
    showDialog = (error, commandName)->
      if error?
        installDirectory = CommandInstaller.getInstallDirectory()
        atom.confirm
          message: error.message
          detailedMessage: "Make sure #{CommandInstaller.getInstallDirectory()} exists and is writable. Run 'sudo mkdir -p #{installDirectory} && sudo chown $USER #{installDirectory}' to fix this problem."
      else
        atom.confirm
          message: "Command installed."
          detailedMessage: "The shell command `#{commandName}` is installed."

    CommandInstaller.installApmCommand (error) =>
      showDialog(error, 'atom')
      unless error?
        CommandInstaller.installApmCommand (error) => showDialog(error, 'apm')

  # Private:
  handleFocus: (e) ->
    if @getActivePane()
      @getActivePane().focus()
      false
    else
      @updateTitle()
      focusableChild = this.find("[tabindex=-1]:visible:first")
      if focusableChild.length
        focusableChild.focus()
        false
      else
        $(document.body).focus()
        true

  # Private:
  afterAttach: (onDom) ->
    @focus() if onDom

  # Public: Shows a dialog asking if the pane was _really_ meant to be closed.
  confirmClose: ->
    @panes.confirmClose()

  # Public: Updates the application's title, based on whichever file is open.
  updateTitle: ->
    if projectPath = atom.project.getPath()
      if item = @getActivePaneItem()
        @setTitle("#{item.getTitle?() ? 'untitled'} - #{projectPath}")
      else
        @setTitle(projectPath)
    else
      @setTitle('untitled')

  # Public: Sets the application's title.
  setTitle: (title) ->
    document.title = title

  # Private: Returns an Array of  all of the application's {EditorView}s.
  getEditorViews: ->
    @panes.find('.pane > .item-views > .editor').map(-> $(this).view()).toArray()

  # Public: Prepends the element to the top of the window.
  prependToTop: (element) ->
    @vertical.prepend(element)

  # Public: Appends the element to the top of the window.
  appendToTop: (element) ->
    @panes.before(element)

  # Public: Prepends the element to the bottom of the window.
  prependToBottom: (element) ->
    @panes.after(element)

  # Public: Appends the element to bottom of the window.
  appendToBottom: (element) ->
    @vertical.append(element)

  # Public: Prepends the element to the left side of the window.
  prependToLeft: (element) ->
    @horizontal.prepend(element)

  # Public: Appends the element to the left side of the window.
  appendToLeft: (element) ->
    @vertical.before(element)

  # Public: Prepends the element to the right side of the window.
  prependToRight: (element) ->
    @vertical.after(element)

  # Public: Appends the element to the right side of the window.
  appendToRight: (element) ->
    @horizontal.append(element)

  # Public: Returns the currently focused {PaneView}.
  getActivePane: ->
    @panes.getActivePane()

  # Public: Returns the currently focused item from within the focused {PaneView}
  getActivePaneItem: ->
    @model.activePaneItem

  # Public: Returns the view of the currently focused item.
  getActiveView: ->
    @panes.getActiveView()

  # Public: Focuses the previous pane by id.
  focusPreviousPane: -> @model.activatePreviousPane()

  # Public: Focuses the next pane by id.
  focusNextPane: -> @model.activateNextPane()

  # Public:
  #
  # FIXME: Difference between active and focused pane?
  getFocusedPane: -> @panes.getFocusedPane()

  # Public: Fires a callback on each open {PaneView}.
  eachPane: (callback) ->
    @panes.eachPane(callback)

  # Public: Returns an Array of all open {PaneView}s.
  getPanes: ->
    @panes.getPanes()

  # Public: Return the id of the given a {PaneView}
  indexOfPane: (pane) ->
    @panes.indexOfPane(pane)

  # Public: Fires a callback on each open {EditorView}.
  eachEditorView: (callback) ->
    callback(editor) for editor in @getEditorViews()
    attachedCallback = (e, editor) -> callback(editor)
    @on('editor:attached', attachedCallback)
    off: => @off('editor:attached', attachedCallback)

  # Private: Called by SpacePen
  beforeRemove: ->
    @model.destroy()

  # Private: Destroys everything.
  remove: ->
    editorView.remove() for editorView in @getEditorViews()
    super
