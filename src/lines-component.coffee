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
      {editor, visibleRowRange, preservedScreenRow, showIndentGuide} = @props
      [startRow, endRow] = visibleRowRange

      style =
        paddingTop: startRow * editor.getLineHeight()
        paddingBottom: (editor.getScreenLineCount() - endRow) * editor.getLineHeight()

      lines =
        for tokenizedLine, i in editor.linesForScreenRows(startRow, endRow - 1)
          LineComponent({key: tokenizedLine.id, tokenizedLine, showIndentGuide, screenRow: startRow + i})

      if preservedScreenRow? and (preservedScreenRow < startRow or endRow <= preservedScreenRow)
        lines.push(LineComponent({key: editor.lineForScreenRow(preservedScreenRow).id, preserved: true}))

    div {className: 'lines', style}, lines

  componentWillMount: ->
    @measuredLines = new WeakSet

  componentDidMount: ->
    @measureLineHeightAndCharWidth()

  shouldComponentUpdate: (newProps) ->
    return true unless isEqualForProperties(newProps, @props,  'visibleRowRange', 'preservedScreenRow', 'fontSize', 'fontFamily', 'lineHeight', 'showIndentGuide')

    {visibleRowRange, pendingChanges} = newProps
    for change in pendingChanges
      return true unless change.end <= visibleRowRange.start or visibleRowRange.end <= change.start

    false

  componentDidUpdate: (prevProps) ->
    @measureLineHeightAndCharWidth() unless isEqualForProperties(prevProps, @props, 'fontSize', 'fontFamily', 'lineHeight')
    @clearScopedCharWidths() unless isEqualForProperties(prevProps, @props, 'fontSize', 'fontFamily')
    @measureCharactersInNewLines() unless @props.preservedScreenRow?

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
    iteratorIndex = -1

    for {value, scopes}, tokenIndex in tokenizedLine.tokens
      charWidths = editor.getScopedCharWidths(scopes)
      for char, i in value
        unless charWidths[char]?
          rangeForMeasurement ?= document.createRange()
          iterator ?=  document.createNodeIterator(lineNode, NodeFilter.SHOW_TEXT, AcceptFilter)

          while iteratorIndex < tokenIndex
            textNode = iterator.nextNode()
            iteratorIndex++

          rangeForMeasurement.setStart(textNode, i)
          rangeForMeasurement.setEnd(textNode, i + 1)
          charWidth = rangeForMeasurement.getBoundingClientRect().width
          editor.setScopedCharWidth(scopes, char, charWidth)

    @measuredLines.add(tokenizedLine)

  clearScopedCharWidths: ->
    @measuredLines.clear()
    @props.editor.clearScopedCharWidths()


LineComponent = React.createClass
  displayName: 'LineComponent'

  render: ->
    {screenRow, preserved} = @props

    div className: 'line', 'data-screen-row': screenRow, dangerouslySetInnerHTML: {__html: @buildInnerHTML()}

  buildInnerHTML: ->
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

  shouldComponentUpdate: (newProps) ->
    return false if newProps.preserved
    not isEqualForProperties(newProps, @props, 'showIndentGuide', 'preserved')
