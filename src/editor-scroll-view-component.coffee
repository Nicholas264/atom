React = require 'react'
{div} = require 'reactionary'
{debounce} = require 'underscore-plus'

InputComponent = require './input-component'
LinesComponent = require './lines-component'
CursorsComponent = require './cursors-component'
SelectionsComponent = require './selections-component'

module.exports =
EditorScrollViewComponent = React.createClass
  displayName: 'EditorScrollViewComponent'

  measurementPending: false
  overflowChangedEventsPaused: false
  overflowChangedWhilePaused: false

  render: ->
    {editor, fontSize, fontFamily, lineHeight, showIndentGuide, cursorBlinkPeriod, cursorBlinkResumeDelay} = @props
    {visibleRowRange, preservedScreenRow, pendingChanges, cursorsMoved, onInputFocused, onInputBlurred} = @props

    if @isMounted()
      contentStyle =
        height: editor.getScrollHeight()
        WebkitTransform: "translate(#{-editor.getScrollLeft()}px, #{-editor.getScrollTop()}px)"

    div className: 'scroll-view',
      InputComponent
        ref: 'input'
        className: 'hidden-input'
        style: @getHiddenInputPosition()
        onInput: @onInput
        onFocus: onInputFocused
        onBlur: onInputBlurred

      div className: 'scroll-view-content', style: contentStyle, onMouseDown: @onMouseDown,
        CursorsComponent({editor, cursorsMoved, cursorBlinkPeriod, cursorBlinkResumeDelay})
        LinesComponent {
          ref: 'lines', editor, fontSize, fontFamily, lineHeight, showIndentGuide,
          visibleRowRange, preservedScreenRow, pendingChanges
        }
        div className: 'underlayer',
          SelectionsComponent({editor})

  componentDidMount: ->
    @getDOMNode().addEventListener 'overflowchanged', @onOverflowChanged
    window.addEventListener('resize', @onWindowResize)

    @measureHeightAndWidth()

  componentDidUnmount: ->
    window.removeEventListener('resize', @onWindowResize)

  componentDidUpdate: ->
    @pauseOverflowChangedEvents()

  onOverflowChanged: ->
    if @overflowChangedEventsPaused
      @overflowChangedWhilePaused = true
    else
      @requestMeasurement()

  onWindowResize: ->
    @requestMeasurement()

  pauseOverflowChangedEvents: ->
    @overflowChangedEventsPaused = true
    @resumeOverflowChangedEventsAfterDelay ?= debounce(@resumeOverflowChangedEvents, 500)
    @resumeOverflowChangedEventsAfterDelay()

  resumeOverflowChangedEvents: ->
    if @overflowChangedWhilePaused
      @overflowChangedWhilePaused = false
      @requestMeasurement()

  resumeOverflowChangedEventsAfterDelay: null

  requestMeasurement: ->
    return if @measurementPending

    @measurementPending = true
    requestAnimationFrame =>
      @measurementPending = false
      @measureHeightAndWidth()

  onInput: (char, replaceLastCharacter) ->
    {editor} = @props

    if replaceLastCharacter
      editor.transact ->
        editor.selectLeft()
        editor.insertText(char)
    else
      editor.insertText(char)

  onMouseDown: (event) ->
    {editor} = @props
    {detail, shiftKey, metaKey} = event
    screenPosition = @screenPositionForMouseEvent(event)

    if shiftKey
      editor.selectToScreenPosition(screenPosition)
    else if metaKey
      editor.addCursorAtScreenPosition(screenPosition)
    else
      editor.setCursorScreenPosition(screenPosition)
      switch detail
        when 2 then editor.selectWord()
        when 3 then editor.selectLine()

    @selectToMousePositionUntilMouseUp(event)

  selectToMousePositionUntilMouseUp: (event) ->
    {editor} = @props
    dragging = false
    lastMousePosition = {}

    animationLoop = =>
      requestAnimationFrame =>
        if dragging
          @selectToMousePosition(lastMousePosition)
          animationLoop()

    onMouseMove = (event) ->
      lastMousePosition.clientX = event.clientX
      lastMousePosition.clientY = event.clientY

      # Start the animation loop when the mouse moves prior to a mouseup event
      unless dragging
        dragging = true
        animationLoop()

      # Stop dragging when cursor enters dev tools because we can't detect mouseup
      onMouseUp() if event.which is 0

    onMouseUp = ->
      dragging = false
      window.removeEventListener('mousemove', onMouseMove)
      window.removeEventListener('mouseup', onMouseUp)
      editor.finalizeSelections()

    window.addEventListener('mousemove', onMouseMove)
    window.addEventListener('mouseup', onMouseUp)

  selectToMousePosition: (event) ->
    @props.editor.selectToScreenPosition(@screenPositionForMouseEvent(event))

  screenPositionForMouseEvent: (event) ->
    pixelPosition = @pixelPositionForMouseEvent(event)
    @props.editor.screenPositionForPixelPosition(pixelPosition)

  pixelPositionForMouseEvent: (event) ->
    {editor} = @props
    {clientX, clientY} = event

    editorClientRect = @getDOMNode().getBoundingClientRect()
    top = clientY - editorClientRect.top + editor.getScrollTop()
    left = clientX - editorClientRect.left + editor.getScrollLeft()
    {top, left}

  getHiddenInputPosition: ->
    return {top: 0, left: 0} unless @isMounted()

    {editor} = @props

    if cursor = editor.getCursor()
      cursorRect = cursor.getPixelRect()
      top = cursorRect.top - editor.getScrollTop()
      top = Math.max(0, Math.min(editor.getHeight(), top))
      left = cursorRect.left - editor.getScrollLeft()
      left = Math.max(0, Math.min(editor.getWidth(), left))
    else
      top = 0
      left = 0

    {top, left}

  # Measure explicitly-styled height and width and relay them to the model. If
  # these values aren't explicitly styled, we assume the editor is unconstrained
  # and use the scrollHeight / scrollWidth as its height and width in
  # calculations.
  measureHeightAndWidth: ->
    return unless @isMounted()

    node = @getDOMNode()
    computedStyle = getComputedStyle(node)
    {editor} = @props

    unless computedStyle.height is '0px'
      clientHeight = node.clientHeight
      editor.setHeight(clientHeight) if clientHeight > 0

    unless computedStyle.width is '0px'
      clientWidth = node.clientWidth
      editor.setWidth(clientWidth) if clientHeight > 0

  focus: ->
    @refs.input.focus()
