React = require 'react'
{div, span} = require 'reactionary'
{debounce, isEqual, isEqualForProperties, multiplyString} = require 'underscore-plus'
{$$} = require 'space-pen'

DummyLineNode = $$(-> @div className: 'line', style: 'position: absolute; visibility: hidden;', => @span 'x')[0]
AcceptFilter = {acceptNode: -> NodeFilter.FILTER_ACCEPT}

module.exports =
LinesComponent = React.createClass
  displayName: 'LinesComponent'

  render: ->
    if @isMounted()
      {editor, visibleRowRange, scrollTop, scrollLeft, lineHeight, showIndentGuide, selectionChanged} = @props
      [startRow, endRow] = visibleRowRange
      selectionRegionsByScreenRow = @getVisibleSelectionRegions()
      verticalScrollOffset = -scrollTop % lineHeight
      horizontalScrollOffset = -scrollLeft

      lines =
        for tokenizedLine, index in editor.linesForScreenRows(startRow, endRow - 1)
          screenRow = startRow + index
          selectionRegions = selectionRegionsByScreenRow[screenRow]
          LineComponent({key: tokenizedLine.id, tokenizedLine, showIndentGuide, lineHeight, index, verticalScrollOffset, horizontalScrollOffset, screenRow, selectionRegions})

    div {className: 'lines'}, lines

  getVisibleSelectionRegions: ->
    {editor, visibleRowRange, lineHeight} = @props
    [visibleStartRow, visibleEndRow] = visibleRowRange
    regions = {}

    for selection in editor.selectionsForScreenRows(visibleStartRow, visibleEndRow - 1) when not selection.isEmpty()
      {start, end} = selection.getScreenRange()

      for screenRow in [start.row..end.row]
        region = {id: selection.id, top: 0, left: 0, height: lineHeight}

        if screenRow is start.row
          region.left = editor.pixelPositionForScreenPosition(start).left
        if screenRow is end.row
          region.width = editor.pixelPositionForScreenPosition(end).left - region.left
        else
          region.right = 0

        regions[screenRow] ?= []
        regions[screenRow].push(region)

    regions

  componentWillMount: ->
    @measuredLines = new WeakSet

  componentDidMount: ->
    @measureLineHeightAndCharWidth()

  shouldComponentUpdate: (newProps) ->
    return true if newProps.selectionChanged
    return true unless isEqualForProperties(newProps, @props,  'visibleRowRange', 'fontSize', 'fontFamily', 'lineHeight', 'scrollTop', 'scrollLeft', 'showIndentGuide', 'scrollingVertically')

    {visibleRowRange, pendingChanges} = newProps
    for change in pendingChanges
      return true unless change.end <= visibleRowRange.start or visibleRowRange.end <= change.start

    false

  componentDidUpdate: (prevProps) ->
    @measureLineHeightAndCharWidth() unless isEqualForProperties(prevProps, @props, 'fontSize', 'fontFamily', 'lineHeight')
    @clearScopedCharWidths() unless isEqualForProperties(prevProps, @props, 'fontSize', 'fontFamily')
    @measureCharactersInNewLines() unless @props.scrollingVertically

  measureLineHeightAndCharWidth: ->
    node = @getDOMNode()
    node.appendChild(DummyLineNode)
    lineHeight = DummyLineNode.getBoundingClientRect().height
    charWidth = DummyLineNode.firstChild.getBoundingClientRect().width
    node.removeChild(DummyLineNode)

    {editor} = @props
    editor.setLineHeight(lineHeight)
    editor.setDefaultCharWidth(charWidth)

  measureCharactersInNewLines: ->
    [visibleStartRow, visibleEndRow] = @props.visibleRowRange
    node = @getDOMNode()

    for tokenizedLine, i in @props.editor.linesForScreenRows(visibleStartRow, visibleEndRow - 1)
      unless @measuredLines.has(tokenizedLine)
        lineNode = node.children[i]
        @measureCharactersInLine(tokenizedLine, lineNode)

  measureCharactersInLine: (tokenizedLine, lineNode) ->
    {editor} = @props
    rangeForMeasurement = null
    iterator = null
    charIndex = 0

    for {value, scopes}, tokenIndex in tokenizedLine.tokens
      charWidths = editor.getScopedCharWidths(scopes)

      for char in value
        unless charWidths[char]?
          unless textNode?
            rangeForMeasurement ?= document.createRange()
            iterator =  document.createNodeIterator(lineNode, NodeFilter.SHOW_TEXT, AcceptFilter)
            textNode = iterator.nextNode()
            textNodeIndex = 0
            nextTextNodeIndex = textNode.textContent.length

          while nextTextNodeIndex <= charIndex
            textNode = iterator.nextNode()
            textNodeIndex = nextTextNodeIndex
            nextTextNodeIndex = textNodeIndex + textNode.textContent.length

          i = charIndex - textNodeIndex
          rangeForMeasurement.setStart(textNode, i)
          rangeForMeasurement.setEnd(textNode, i + 1)
          charWidth = rangeForMeasurement.getBoundingClientRect().width
          editor.setScopedCharWidth(scopes, char, charWidth)

        charIndex++

    @measuredLines.add(tokenizedLine)

  clearScopedCharWidths: ->
    @measuredLines.clear()
    @props.editor.clearScopedCharWidths()


LineComponent = React.createClass
  displayName: 'LineComponent'

  render: ->
    {index, screenRow, verticalScrollOffset, horizontalScrollOffset, lineHeight} = @props

    top = index * lineHeight + verticalScrollOffset
    left = horizontalScrollOffset
    style = WebkitTransform: "translate3d(#{left}px, #{top}px, 0px)"

    div className: 'line editor-colors', style: style, 'data-screen-row': screenRow,
      span dangerouslySetInnerHTML: {__html: @buildTokensHTML()}
      @renderSelections()

  buildTokensHTML: ->
    if @props.tokenizedLine.text.length is 0
      @buildEmptyLineHTML()
    else
      @buildScopeTreeHTML(@props.tokenizedLine.getScopeTree())

  buildEmptyLineHTML: ->
    {showIndentGuide, tokenizedLine} = @props
    {indentLevel, tabLength} = tokenizedLine

    if showIndentGuide and indentLevel > 0
      indentSpan = "<span class='indent-guide'>#{multiplyString(' ', tabLength)}</span>"
      multiplyString(indentSpan, indentLevel + 1)
    else
      "&nbsp;"

  buildScopeTreeHTML: (scopeTree) ->
    if scopeTree.children?
      html = "<span class='#{scopeTree.scope.replace(/\./g, ' ')}'>"
      html += @buildScopeTreeHTML(child) for child in scopeTree.children
      html += "</span>"
      html
    else
      "<span>#{scopeTree.getValueAsHtml({hasIndentGuide: @props.showIndentGuide})}</span>"

  renderSelections: ->
    {selectionRegions} = @props
    if selectionRegions?
      for region in selectionRegions
        div className: 'selection', key: region.id,
          div className: 'region', style: region

  shouldComponentUpdate: (newProps) ->
    return true unless isEqualForProperties(newProps, @props, 'showIndentGuide', 'lineHeight', 'screenRow', 'selectionRegions', 'index', 'verticalScrollOffset', 'horizontalScrollOffset')
