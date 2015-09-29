ipc = require 'ipc'
path = require 'path'
{Disposable, CompositeDisposable} = require 'event-kit'
Grim = require 'grim'
scrollbarStyle = require 'scrollbar-style'

module.exports =
class WorkspaceElement extends HTMLElement
  globalTextEditorStyleSheet: null

  createdCallback: ->
    @subscriptions = new CompositeDisposable
    @initializeContent()
    @observeScrollbarStyle()
    @observeTextEditorFontConfig()

  attachedCallback: ->
    @focus()

  detachedCallback: ->
    @subscriptions.dispose()
    @model.destroy()

  initializeContent: ->
    @classList.add 'workspace'
    @setAttribute 'tabindex', -1

    @verticalAxis = document.createElement('atom-workspace-axis')
    @verticalAxis.classList.add('vertical')

    @horizontalAxis = document.createElement('atom-workspace-axis')
    @horizontalAxis.classList.add('horizontal')
    @horizontalAxis.appendChild(@verticalAxis)

    @appendChild(@horizontalAxis)

  observeScrollbarStyle: ->
    @subscriptions.add scrollbarStyle.observePreferredScrollbarStyle (style) =>
      switch style
        when 'legacy'
          @classList.remove('scrollbars-visible-when-scrolling')
          @classList.add("scrollbars-visible-always")
        when 'overlay'
          @classList.remove('scrollbars-visible-always')
          @classList.add("scrollbars-visible-when-scrolling")

  observeTextEditorFontConfig: ->
    @updateGlobalTextEditorStyleSheet()
    @subscriptions.add atom.config.onDidChange 'editor.fontSize', @updateGlobalTextEditorStyleSheet.bind(this)
    @subscriptions.add atom.config.onDidChange 'editor.fontFamily', @updateGlobalTextEditorStyleSheet.bind(this)
    @subscriptions.add atom.config.onDidChange 'editor.lineHeight', @updateGlobalTextEditorStyleSheet.bind(this)

  updateGlobalTextEditorStyleSheet: ->
    styleSheetSource = """
      atom-text-editor {
        font-size: #{atom.config.get('editor.fontSize')}px;
        font-family: #{atom.config.get('editor.fontFamily')};
        line-height: #{atom.config.get('editor.lineHeight')};
      }
    """
    atom.styles.addStyleSheet(styleSheetSource, sourcePath: 'global-text-editor-styles')

  initialize: (@model) ->
    @paneContainer = atom.views.getView(@model.paneContainer)
    @verticalAxis.appendChild(@paneContainer)
    @addEventListener 'focus', @handleFocus.bind(this)

    @panelContainers =
      top: atom.views.getView(@model.panelContainers.top)
      left: atom.views.getView(@model.panelContainers.left)
      right: atom.views.getView(@model.panelContainers.right)
      bottom: atom.views.getView(@model.panelContainers.bottom)
      modal: atom.views.getView(@model.panelContainers.modal)

    @horizontalAxis.insertBefore(@panelContainers.left, @verticalAxis)
    @horizontalAxis.appendChild(@panelContainers.right)

    @verticalAxis.insertBefore(@panelContainers.top, @paneContainer)
    @verticalAxis.appendChild(@panelContainers.bottom)

    @appendChild(@panelContainers.modal)

    this

  getModel: -> @model

  handleFocus: (event) ->
    @model.getActivePane().activate()

  focusPaneViewAbove: -> @paneContainer.focusPaneViewAbove()

  focusPaneViewBelow: -> @paneContainer.focusPaneViewBelow()

  focusPaneViewOnLeft: -> @paneContainer.focusPaneViewOnLeft()

  focusPaneViewOnRight: -> @paneContainer.focusPaneViewOnRight()

  runPackageSpecs: ->
    if activePath = atom.workspace.getActivePaneItem()?.getPath?()
      [projectPath] = atom.project.relativizePath(activePath)
    else
      [projectPath] = atom.project.getPaths()
    ipc.send('run-package-specs', path.join(projectPath, 'spec')) if projectPath

module.exports = WorkspaceElement = document.registerElement 'atom-workspace', prototype: WorkspaceElement.prototype
