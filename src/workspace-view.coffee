ipc = require 'ipc'
path = require 'path'
Q = require 'q'
_ = require 'underscore-plus'
Delegator = require 'delegato'
{$, $$, View} = require './space-pen-extensions'
fs = require 'fs-plus'
Serializable = require 'serializable'
Workspace = require './workspace'
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
module.exports =
class WorkspaceView extends View
  atom.deserializers.add(this, PaneView, PaneRowView, PaneColumnView, EditorView)
  Serializable.includeInto(this)
  Delegator.includeInto(this)

  @delegatesProperty 'fullScreen', toProperty: 'model'

  @version: 4

  @deserialize: (state) ->
    new this(Workspace.deserialize(state.model))

  @configDefaults:
    ignoredNames: [".git", ".svn", ".DS_Store"]
    excludeVcsIgnoredPaths: true
    disabledPackages: []
    themes: ['atom-dark-ui', 'atom-dark-syntax']
    projectHome: path.join(fs.getHomeDirectory(), 'github')
    audioBeep: true

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

    @destroyedItemUris = []
    @subscribe @panes, 'item-destroyed', @onPaneItemDestroyed

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

    @command 'core:close', => @destroyActivePaneItem()
    @command 'core:save', => @saveActivePaneItem()
    @command 'core:save-as', => @saveActivePaneItemAs()

  # Private:
  serializeParams: ->
    model: @model.serialize()

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

  # Public: Asynchronously opens a given a filepath in Atom.
  #
  # * filePath: A file path
  # * options
  #   + initialLine: The buffer line number to open to.
  #
  # Returns a promise that resolves to the {Editor} for the file URI.
  open: (filePath, options={}) ->
    changeFocus = options.changeFocus ? true
    filePath = atom.project.resolve(filePath)
    initialLine = options.initialLine
    activePane = @getActivePane()

    editor = activePane.itemForUri(atom.project.relativize(filePath)) if activePane and filePath
    promise = atom.project.open(filePath, {initialLine}) if not editor

    Q(editor ? promise)
      .then (editor) =>
        if not activePane
          activePane = new PaneView(editor)
          @panes.setRoot(activePane)

        @itemOpened(editor)
        activePane.activateItem(editor)
        activePane.activate() if changeFocus
        @trigger "uri-opened"
        editor
      .catch (error) ->
        console.error(error.stack ? error)

  # Private: Only used in specs
  openSync: (uri, {changeFocus, initialLine, pane, split}={}) ->
    changeFocus ?= true
    pane ?= @getActivePane()
    uri = atom.project.relativize(uri)

    if pane
      if uri
        paneItem = pane.itemForUri(uri) ? atom.project.openSync(uri, {initialLine})
      else
        paneItem = atom.project.openSync()

      if split == 'right'
        panes = @getPanes()
        if panes.length == 1
          pane = panes[0].splitRight()
        else
          pane = _.last(panes)
      else if split == 'left'
        pane = @getPanes()[0]

      pane.activateItem(paneItem)
    else
      paneItem = atom.project.openSync(uri, {initialLine})
      pane = new PaneView(paneItem)
      @panes.setRoot(pane)

    @itemOpened(paneItem)

    pane.activate() if changeFocus
    paneItem

  openSingletonSync: (uri, {changeFocus, initialLine, split}={}) ->
    changeFocus ?= true
    uri = atom.project.relativize(uri)
    pane = @panes.paneForUri(uri)

    if pane
      paneItem = pane.itemForUri(uri)
      pane.activateItem(paneItem)
      pane.activate() if changeFocus
      paneItem
    else
      @openSync(uri, {changeFocus, initialLine, split})

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

  # Private: Retrieves all of the modified buffers that are open and unsaved.
  #
  # Returns an {Array} of {TextBuffer}s.
  getModifiedBuffers: ->
    modifiedBuffers = []
    for pane in @getPanes()
      for item in pane.getItems() when item instanceof Editor
        modifiedBuffers.push item.buffer if item.buffer.isModified()
    modifiedBuffers

  # Private: Retrieves all of the paths to open files.
  #
  # Returns an {Array} of {String}s.
  getOpenBufferPaths: ->
    _.uniq(_.flatten(@getEditorViews().map (editorView) -> editorView.getOpenBufferPaths()))

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
    @panes.getActivePaneItem()

  # Public: Returns the view of the currently focused item.
  getActiveView: ->
    @panes.getActiveView()

  # Public: destroy/close the active item.
  destroyActivePaneItem: ->
    @getActivePane()?.destroyActiveItem()

  # Public: save the active item.
  saveActivePaneItem: ->
    @getActivePane()?.saveActiveItem()

  # Public: save the active item as.
  saveActivePaneItemAs: ->
    @getActivePane()?.saveActiveItemAs()

  # Public: Focuses the previous pane by id.
  focusPreviousPane: -> @panes.focusPreviousPane()

  # Public: Focuses the next pane by id.
  focusNextPane: -> @panes.focusNextPane()

  # Public:
  #
  # FIXME: Difference between active and focused pane?
  getFocusedPane: -> @panes.getFocusedPane()

  # Public: Saves all of the open items within panes.
  saveAll: ->
    @panes.saveAll()

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

  # Private: Destroys everything.
  remove: ->
    editorView.remove() for editorView in @getEditorViews()
    super

  # Private: Adds the destroyed item's uri to the list of items to reopen.
  onPaneItemDestroyed: (e, item) =>
    if uri = item.getUri?()
      @destroyedItemUris.push(uri)

  # Public: Reopens the last-closed item uri if it hasn't already been reopened.
  reopenItemSync: ->
    if uri = @destroyedItemUris.pop()
      @openSync(uri)

  # Private: Removes the item's uri from the list of potential items to reopen.
  itemOpened: (item) ->
    if uri = item.getUri?()
      _.remove(@destroyedItemUris, uri)
