{View, $$, $$$} = require './space-pen-extensions'
{Range} = require 'telepath'
$ = require './jquery-extensions'
_ = require './underscore-extensions'

# Private: Represents the portion of the {Editor} containing row numbers.
#
# The gutter also indicates if rows are folded.
module.exports =
class Gutter extends View

  ### Internal ###

  @content: ->
    @div class: 'gutter', =>
      @div outlet: 'lineNumbers', class: 'line-numbers'

  firstScreenRow: Infinity
  lastScreenRow: -1

  afterAttach: (onDom) ->
    return if @attached or not onDom
    @attached = true

    highlightLines = => @highlightLines()
    @getEditor().on 'cursor:moved', highlightLines
    @getEditor().on 'selection:changed', highlightLines
    @on 'mousedown', (e) => @handleMouseEvents(e)

  beforeRemove: ->
    $(document).off(".gutter-#{@getEditor().id}")

  handleMouseEvents: (e) ->
    editor = @getEditor()
    startRow = editor.screenPositionFromMouseEvent(e).row
    if e.shiftKey
      editor.selectToScreenPosition([startRow + 1, 0])
      return
    else
      editor.getSelection().setScreenRange([[startRow, 0], [startRow, 0]])

    moveHandler = (e) =>
      start = startRow
      end = editor.screenPositionFromMouseEvent(e).row
      if end > start then end++ else start++
      editor.getSelection().setScreenRange([[start, 0], [end, 0]])

    $(document).on "mousemove.gutter-#{@getEditor().id}", moveHandler
    $(document).one "mouseup.gutter-#{@getEditor().id}", => $(document).off 'mousemove', moveHandler

  ### Public ###

  # Retrieves the containing {Editor}.
  #
  # Returns an {Editor}.
  getEditor: ->
    @parentView

  # Defines whether to show the gutter or not.
  #
  # showLineNumbers - A {Boolean} which, if `false`, hides the gutter
  setShowLineNumbers: (showLineNumbers) ->
    if showLineNumbers then @lineNumbers.show() else @lineNumbers.hide()

  # Get all the line-number divs.
  #
  # Returns a list of {HTMLElement}s.
  getLineNumberElements: ->
    @lineNumbers[0].getElementsByClassName('line-number')

  # Get a single line-number div.
  #
  # * lineNumber: 0 based line number
  #
  # Returns a {HTMLElement}
  getLineNumberElement: (lineNumber) ->
    @lineNumbers[0].getElementsByClassName("line-number-#{lineNumber}")[0]

  # Add a class to all line-number divs.
  #
  # * clas: string class name
  #
  # Returns a list of {HTMLElement}s.
  addClassToAllLines: (clas)->
    $.fn.addClass.call(@getLineNumberElements(), clas)

  # Remove a class from all line-number divs.
  #
  # * clas: string class name
  #
  # Returns a list of {HTMLElement}s.
  removeClassFromAllLines: (clas)->
    $.fn.removeClass.call(@getLineNumberElements(), clas)

  # Add a class to a single line-number div
  #
  # * lineNumber: 0 based line number
  # * clas: string class name
  #
  # Returns the {HTMLElement} on which the class was set. undefined if the line was not found
  addClassToLine: (lineNumber, clas)->
    line = @lineNumbers[0].getElementsByClassName("line-number-#{lineNumber}")
    $.fn.addClass.call(line, clas) if line

  # Remove a class from a single line-number div
  #
  # * lineNumber: 0 based line number
  # * clas: string class name
  #
  # Returns the {HTMLElement} on which the class was set. undefined if the line was not found
  removeClassFromLine: (lineNumber, clas)->
    line = @lineNumbers[0].getElementsByClassName("line-number-#{lineNumber}")
    $.fn.removeClass.call(line, clas) if line

  ### Internal ###

  updateLineNumbers: (changes, renderFrom, renderTo) ->
    if renderFrom < @firstScreenRow or renderTo > @lastScreenRow
      performUpdate = true
    else if @getEditor().getLastScreenRow() < @lastScreenRow
      performUpdate = true
    else
      for change in changes
        if change.screenDelta or change.bufferDelta
          performUpdate = true
          break

    @renderLineNumbers(renderFrom, renderTo) if performUpdate

  renderLineNumbers: (startScreenRow, endScreenRow) ->
    @lineNumbers[0].innerHTML = @buildLineElementsHtml(startScreenRow, endScreenRow)
    @firstScreenRow = startScreenRow
    @lastScreenRow = endScreenRow
    @highlightedRows = null
    @highlightLines()

  buildLineElementsHtml: (startScreenRow, endScreenRow) =>
    editor = @getEditor()
    maxDigits = editor.getLineCount().toString().length
    rows = editor.bufferRowsForScreenRows(startScreenRow, endScreenRow)

    html = ''
    for row in rows
      if row == lastScreenRow
        rowValue = '•'
      else
        rowValue = (row + 1).toString()

      classes = "line-number line-number-#{row}"
      classes += ' fold' if editor.isFoldedAtBufferRow(row)

      rowValuePadding = _.multiplyString('&nbsp;', maxDigits - rowValue.length)

      html += """<div class="#{classes}">#{rowValuePadding}#{rowValue}</div>"""

      lastScreenRow = row

    html

  removeLineHighlights: ->
    return unless @highlightedLineNumbers
    for line in @highlightedLineNumbers
      line.classList.remove('cursor-line')
      line.classList.remove('cursor-line-no-selection')
    @highlightedLineNumbers = null

  addLineHighlight: (row, emptySelection) ->
    return if row < @firstScreenRow or row > @lastScreenRow
    @highlightedLineNumbers ?= []
    if highlightedLineNumber = @lineNumbers[0].children[row - @firstScreenRow]
      highlightedLineNumber.classList.add('cursor-line')
      highlightedLineNumber.classList.add('cursor-line-no-selection') if emptySelection
      @highlightedLineNumbers.push(highlightedLineNumber)

  highlightLines: ->
    if @getEditor().getSelection().isEmpty()
      row = @getEditor().getCursorScreenPosition().row
      rowRange = new Range([row, 0], [row, 0])
      return if @selectionEmpty and @highlightedRows?.isEqual(rowRange)

      @removeLineHighlights()
      @addLineHighlight(row, true)
      @highlightedRows = rowRange
      @selectionEmpty = true
    else
      selectedRows = @getEditor().getSelection().getScreenRange()
      endRow = selectedRows.end.row
      endRow-- if selectedRows.end.column is 0
      selectedRows = new Range([selectedRows.start.row, 0], [endRow, 0])
      return if not @selectionEmpty and @highlightedRows?.isEqual(selectedRows)

      @removeLineHighlights()
      for row in [selectedRows.start.row..selectedRows.end.row]
        @addLineHighlight(row, false)
      @highlightedRows = selectedRows
      @selectionEmpty = false
