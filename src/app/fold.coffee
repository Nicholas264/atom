Range = require 'range'
Point = require 'point'

# Public: Represents a fold in the {Gutter}.
#
# Folds hide away text from the screen. They're the primary reason
# that screen ranges and buffer ranges vary.
module.exports =
class Fold
  @idCounter: 1

  displayBuffer: null
  startRow: null
  endRow: null

  # Internal: 
  constructor: (@displayBuffer, @startRow, @endRow) ->
    @id = @constructor.idCounter++

  # Internal: 
  destroy: ->
    @displayBuffer.destroyFold(this)

  # Internal: 
  inspect: ->
    "Fold(#{@startRow}, #{@endRow})"

  # Public: Retrieves the buffer row range that a fold occupies.
  #
  # includeNewline - A {Boolean} which, if `true`, includes the trailing newline
  #
  # Returns a {Range}.
  getBufferRange: ({includeNewline}={}) ->
    if includeNewline
      end = [@endRow + 1, 0]
    else
      end = [@endRow, Infinity]

    new Range([@startRow, 0], end)

  # Public: Retrieves the number of buffer rows a fold occupies.
  #
  # Returns a {Number}.
  getBufferRowCount: ->
    @endRow - @startRow + 1

  # Internal:
  handleBufferChange: (event) ->
    oldStartRow = @startRow

    if @isContainedByRange(event.oldRange)
      @displayBuffer.unregisterFold(@startRow, this)
      return

    @startRow += @getRowDelta(event, @startRow)
    @endRow += @getRowDelta(event, @endRow)

    if @startRow != oldStartRow
      @displayBuffer.unregisterFold(oldStartRow, this)
      @displayBuffer.registerFold(this)

  # Public: Identifies if a {Range} occurs within a fold.
  #
  # range - A {Range} to check
  #
  # Returns a {Boolean}.
  isContainedByRange: (range) ->
    range.start.row <= @startRow and @endRow <= range.end.row

  # Public: Identifies if a fold is nested within a fold.
  #
  # fold - A {Fold} to check
  #
  # Returns a {Boolean}.
  isContainedByFold: (fold) ->
    @isContainedByRange(fold.getBufferRange())

  # Internal:
  getRowDelta: (event, row) ->
    { newRange, oldRange } = event

    if oldRange.end.row <= row
      newRange.end.row - oldRange.end.row
    else if newRange.end.row < row
      newRange.end.row - row
    else
      0
