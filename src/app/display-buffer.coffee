_ = require 'underscore'
TokenizedBuffer = require 'tokenized-buffer'
LineMap = require 'line-map'
Point = require 'point'
EventEmitter = require 'event-emitter'
Range = require 'range'
Fold = require 'fold'
ScreenLine = require 'screen-line'
Token = require 'token'
DisplayBufferMarker = require 'display-buffer-marker'

module.exports =
class DisplayBuffer
  @idCounter: 1
  lineMap: null
  languageMode: null
  tokenizedBuffer: null
  activeFolds: null
  foldsById: null
  markers: null

  ###
  # Internal #
  ###

  constructor: (@buffer, options={}) ->
    @id = @constructor.idCounter++
    @languageMode = options.languageMode
    @tokenizedBuffer = new TokenizedBuffer(@buffer, options)
    @softWrapColumn = options.softWrapColumn ? Infinity
    @activeFolds = {}
    @foldsById = {}
    @markers = {}
    @buildLineMap()
    @tokenizedBuffer.on 'changed', @handleTokenizedBufferChange
    @buffer.on 'markers-updated', @handleMarkersUpdated

  buildLineMap: ->
    @lineMap = new LineMap
    @lineMap.insertAtScreenRow 0, @buildLinesForBufferRows(0, @buffer.getLastRow())

  triggerChanged: (eventProperties, refreshMarkers=true) ->
    if refreshMarkers
      @pauseMarkerObservers()
      @refreshMarkerScreenPositions()
    @trigger 'changed', eventProperties
    @resumeMarkerObservers()

  ###
  # Public #
  ###

  setVisible: (visible) -> @tokenizedBuffer.setVisible(visible)

  # Public: Defines the limit at which the buffer begins to soft wrap text.
  #
  # softWrapColumn - A {Number} defining the soft wrap limit.
  setSoftWrapColumn: (@softWrapColumn) ->
    start = 0
    end = @getLastRow()
    @buildLineMap()
    screenDelta = @getLastRow() - end
    bufferDelta = 0
    @triggerChanged({ start, end, screenDelta, bufferDelta })

  # Public: Gets the screen line for the given screen row.
  #
  # screenRow - A {Number} indicating the screen row.
  #
  # Returns a {ScreenLine}.
  lineForRow: (row) ->
    @lineMap.lineForScreenRow(row)

  # Public: Gets the screen lines for the given screen row range.
  #
  # startRow - A {Number} indicating the beginning screen row.
  # endRow - A {Number} indicating the ending screen row.
  #
  # Returns an {Array} of {ScreenLine}s.
  linesForRows: (startRow, endRow) ->
    @lineMap.linesForScreenRows(startRow, endRow)

  # Public: Gets all the screen lines.
  #
  # Returns an {Array} of {ScreenLines}s.
  getLines: ->
    @lineMap.linesForScreenRows(0, @lineMap.lastScreenRow())


  # Public: Given starting and ending screen rows, this returns an array of the
  # buffer rows corresponding to every screen row in the range
  #
  # startRow - The screen row {Integer} to start at
  # endRow - The screen row {Integer} to end at (default: {.lastScreenRow})
  #
  # Returns an {Array} of buffer rows as {Integers}s.
  bufferRowsForScreenRows: (startRow, endRow) ->
    @lineMap.bufferRowsForScreenRows(startRow, endRow)

  # Public: Folds all the foldable lines in the buffer.
  foldAll: ->
    for currentRow in [0..@buffer.getLastRow()]
      [startRow, endRow] = @languageMode.rowRangeForFoldAtBufferRow(currentRow) ? []
      continue unless startRow?

      @createFold(startRow, endRow)

  # Public: Unfolds all the foldable lines in the buffer.
  unfoldAll: ->
    for row in [@buffer.getLastRow()..0]
      @activeFolds[row]?.forEach (fold) => @destroyFold(fold)

  rowRangeForCommentAtBufferRow: (row) ->
    return unless @tokenizedBuffer.lineForScreenRow(row).isComment()

    startRow = row
    for currentRow in [row-1..0]
      break if @buffer.isRowBlank(currentRow)
      break unless @tokenizedBuffer.lineForScreenRow(currentRow).isComment()
      startRow = currentRow
    endRow = row
    for currentRow in [row+1..@buffer.getLastRow()]
      break if @buffer.isRowBlank(currentRow)
      break unless @tokenizedBuffer.lineForScreenRow(currentRow).isComment()
      endRow = currentRow
    return [startRow, endRow] if startRow isnt endRow

  # Public: Given a buffer row, this folds it.
  #
  # bufferRow - A {Number} indicating the buffer row
  foldBufferRow: (bufferRow) ->
    for currentRow in [bufferRow..0]
      rowRange = @rowRangeForCommentAtBufferRow(currentRow)
      rowRange ?= @languageMode.rowRangeForFoldAtBufferRow(currentRow)
      [startRow, endRow] = rowRange ? []
      continue unless startRow? and startRow <= bufferRow <= endRow
      fold = @largestFoldStartingAtBufferRow(startRow)
      continue if fold

      @createFold(startRow, endRow)

      return

  # Public: Given a buffer row, this unfolds it.
  #
  # bufferRow - A {Number} indicating the buffer row
  unfoldBufferRow: (bufferRow) ->
    @largestFoldContainingBufferRow(bufferRow)?.destroy()

  # Public: Creates a new fold between two row numbers.
  #
  # startRow - The row {Number} to start folding at
  # endRow - The row {Number} to end the fold
  #
  # Returns the new {Fold}.
  createFold: (startRow, endRow) ->
    return fold if fold = @foldFor(startRow, endRow)
    fold = new Fold(this, startRow, endRow)
    @registerFold(fold)

    unless @isFoldContainedByActiveFold(fold)
      bufferRange = new Range([startRow, 0], [endRow, @buffer.lineLengthForRow(endRow)])
      oldScreenRange = @screenLineRangeForBufferRange(bufferRange)

      lines = @buildLineForBufferRow(startRow)
      @lineMap.replaceScreenRows(oldScreenRange.start.row, oldScreenRange.end.row, lines)
      newScreenRange = @screenLineRangeForBufferRange(bufferRange)

      start = oldScreenRange.start.row
      end = oldScreenRange.end.row
      screenDelta = newScreenRange.end.row - oldScreenRange.end.row
      bufferDelta = 0
      @triggerChanged({ start, end, screenDelta, bufferDelta })

    fold

  # Public: Given a {Fold}, determines if it is contained within another fold.
  #
  # fold - The {Fold} to check
  #
  # Returns the contaiing {Fold} (if it exists), `null` otherwise.
  isFoldContainedByActiveFold: (fold) ->
    for row, folds of @activeFolds
      for otherFold in folds
        return otherFold if fold != otherFold and fold.isContainedByFold(otherFold)

  # Public: Given a starting and ending row, tries to find an existing fold.
  #
  # startRow - A {Number} representing a fold's starting row
  # endRow - A {Number} representing a fold's ending row
  #
  # Returns a {Fold} (if it exists).
  foldFor: (startRow, endRow) ->
    _.find @activeFolds[startRow] ? [], (fold) ->
      fold.startRow == startRow and fold.endRow == endRow

  # Public: Removes any folds found that contain the given buffer row.
  #
  # bufferRow - The buffer row {Number} to check against
  destroyFoldsContainingBufferRow: (bufferRow) ->
    for row, folds of @activeFolds
      for fold in new Array(folds...)
        fold.destroy() if fold.getBufferRange().containsRow(bufferRow)

  # Public: Given a buffer row, this returns the largest fold that starts there.
  #
  # Largest is defined as the fold whose difference between its start and end points
  # are the greatest.
  #
  # bufferRow - A {Number} indicating the buffer row
  #
  # Returns a {Fold}.
  largestFoldStartingAtBufferRow: (bufferRow) ->
    return unless folds = @activeFolds[bufferRow]
    (folds.sort (a, b) -> b.endRow - a.endRow)[0]

  # Public: Given a screen row, this returns the largest fold that starts there.
  #
  # Largest is defined as the fold whose difference between its start and end points
  # are the greatest.
  #
  # screenRow - A {Number} indicating the screen row
  #
  # Returns a {Fold}.
  largestFoldStartingAtScreenRow: (screenRow) ->
    @largestFoldStartingAtBufferRow(@bufferRowForScreenRow(screenRow))

  # Public: Given a buffer row, this returns the largest fold that includes it.
  #
  # Largest is defined as the fold whose difference between its start and end points
  # are the greatest.
  #
  # bufferRow - A {Number} indicating the buffer row
  #
  # Returns a {Fold}.
  largestFoldContainingBufferRow: (bufferRow) ->
    largestFold = null
    for currentBufferRow in [bufferRow..0]
      if fold = @largestFoldStartingAtBufferRow(currentBufferRow)
        largestFold = fold if fold.endRow >= bufferRow
    largestFold

  # Public: Given a buffer range, this converts it into a screen range.
  #
  # bufferRange - A {Range} consisting of buffer positions
  #
  # Returns a {Range}.
  screenLineRangeForBufferRange: (bufferRange) ->
    @expandScreenRangeToLineEnds(
      @lineMap.screenRangeForBufferRange(
        @expandBufferRangeToLineEnds(bufferRange)))

  # Public: Given a buffer row, this converts it into a screen row.
  #
  # bufferRow - A {Number} representing a buffer row
  #
  # Returns a {Number}.
  screenRowForBufferRow: (bufferRow) ->
    @lineMap.screenPositionForBufferPosition([bufferRow, 0]).row

  lastScreenRowForBufferRow: (bufferRow) ->
    @lineMap.screenPositionForBufferPosition([bufferRow, Infinity]).row

  # Public: Given a screen row, this converts it into a buffer row.
  #
  # screenRow - A {Number} representing a screen row
  #
  # Returns a {Number}.
  bufferRowForScreenRow: (screenRow) ->
    @lineMap.bufferPositionForScreenPosition([screenRow, 0]).row

  # Public: Given a buffer range, this converts it into a screen position.
  #
  # bufferRange - The {Range} to convert
  #
  # Returns a {Range}.
  screenRangeForBufferRange: (bufferRange) ->
    @lineMap.screenRangeForBufferRange(bufferRange)

  # Public: Given a screen range, this converts it into a buffer position.
  #
  # screenRange - The {Range} to convert
  #
  # Returns a {Range}.
  bufferRangeForScreenRange: (screenRange) ->
    @lineMap.bufferRangeForScreenRange(screenRange)

  # Public: Gets the number of lines in the buffer.
  #
  # Returns a {Number}.
  lineCount: ->
    @lineMap.screenLineCount()

  # Public: Gets the number of the last row in the buffer.
  #
  # Returns a {Number}.
  getLastRow: ->
    @lineCount() - 1

  # Public: Gets the length of the longest screen line.
  #
  # Returns a {Number}.
  maxLineLength: ->
    @lineMap.maxScreenLineLength

  # Public: Given a buffer position, this converts it into a screen position.
  #
  # bufferPosition - An object that represents a buffer position. It can be either
  #                  an {Object} (`{row, column}`), {Array} (`[row, column]`), or {Point}
  # options - A hash of options with the following keys:
  #           :wrapBeyondNewlines -
  #           :wrapAtSoftNewlines -
  #
  # Returns a {Point}.
  screenPositionForBufferPosition: (position, options) ->
    @lineMap.screenPositionForBufferPosition(position, options)

  # Public: Given a buffer range, this converts it into a screen position.
  #
  # screenPosition - An object that represents a buffer position. It can be either
  #                  an {Object} (`{row, column}`), {Array} (`[row, column]`), or {Point}
  # options - A hash of options with the following keys:
  #           :wrapBeyondNewlines -
  #           :wrapAtSoftNewlines -
  #
  # Returns a {Point}.
  bufferPositionForScreenPosition: (position, options) ->
    @lineMap.bufferPositionForScreenPosition(position, options)

  # Public: Retrieves the grammar's token scopes for a buffer position.
  #
  # bufferPosition - A {Point} in the {Buffer}
  #
  # Returns an {Array} of {String}s.
  scopesForBufferPosition: (bufferPosition) ->
    @tokenizedBuffer.scopesForPosition(bufferPosition)

  # Public: Retrieves the grammar's token for a buffer position.
  #
  # bufferPosition - A {Point} in the {Buffer}.
  #
  # Returns a {Token}.
  tokenForBufferPosition: (bufferPosition) ->
    @tokenizedBuffer.tokenForPosition(bufferPosition)

  # Public: Retrieves the current tab length.
  #
  # Returns a {Number}.
  getTabLength: ->
    @tokenizedBuffer.getTabLength()

  # Public: Specifies the tab length.
  #
  # tabLength - A {Number} that defines the new tab length.
  setTabLength: (tabLength) ->
    @tokenizedBuffer.setTabLength(tabLength)

  # Public: Given a position, this clips it to a real position.
  #
  # For example, if `position`'s row exceeds the row count of the buffer,
  # or if its column goes beyond a line's length, this "sanitizes" the value
  # to a real position.
  #
  # position - The {Point} to clip
  # options - A hash with the following values:
  #           :wrapBeyondNewlines - if `true`, continues wrapping past newlines
  #           :wrapAtSoftNewlines - if `true`, continues wrapping past soft newlines
  #           :screenLine - if `true`, indicates that you're using a line number, not a row number
  #
  # Returns the new, clipped {Point}. Note that this could be the same as `position` if no clipping was performed.
  clipScreenPosition: (position, options) ->
    @lineMap.clipScreenPosition(position, options)

  ###
  # Internal #
  ###

  registerFold: (fold) ->
    @activeFolds[fold.startRow] ?= []
    @activeFolds[fold.startRow].push(fold)
    @foldsById[fold.id] = fold

  unregisterFold: (bufferRow, fold) ->
    folds = @activeFolds[bufferRow]
    _.remove(folds, fold)
    delete @foldsById[fold.id]
    delete @activeFolds[bufferRow] if folds.length == 0

  destroyFold: (fold) ->
    @unregisterFold(fold.startRow, fold)

    unless @isFoldContainedByActiveFold(fold)
      { startRow, endRow } = fold
      bufferRange = new Range([startRow, 0], [endRow, @buffer.lineLengthForRow(endRow)])
      oldScreenRange = @screenLineRangeForBufferRange(bufferRange)
      lines = @buildLinesForBufferRows(startRow, endRow)
      @lineMap.replaceScreenRows(oldScreenRange.start.row, oldScreenRange.end.row, lines)
      newScreenRange = @screenLineRangeForBufferRange(bufferRange)

      start = oldScreenRange.start.row
      end = oldScreenRange.end.row
      screenDelta = newScreenRange.end.row - oldScreenRange.end.row
      bufferDelta = 0

      @triggerChanged({ start, end, screenDelta, bufferDelta })

  handleBufferChange: (e) ->
    allFolds = [] # Folds can modify @activeFolds, so first make sure we have a stable array of folds
    allFolds.push(folds...) for row, folds of @activeFolds
    fold.handleBufferChange(e) for fold in allFolds

  handleTokenizedBufferChange: (tokenizedBufferChange) =>
    if bufferChange = tokenizedBufferChange.bufferChange
      @handleBufferChange(bufferChange)
      bufferDelta = bufferChange.newRange.end.row - bufferChange.oldRange.end.row

    tokenizedBufferStart = @bufferRowForScreenRow(@screenRowForBufferRow(tokenizedBufferChange.start))
    tokenizedBufferEnd = tokenizedBufferChange.end
    tokenizedBufferDelta = tokenizedBufferChange.delta

    start = @screenRowForBufferRow(tokenizedBufferStart)
    end = @lastScreenRowForBufferRow(tokenizedBufferEnd)
    newScreenLines = @buildLinesForBufferRows(tokenizedBufferStart, tokenizedBufferEnd + tokenizedBufferDelta)
    @lineMap.replaceScreenRows(start, end, newScreenLines)
    screenDelta = @lastScreenRowForBufferRow(tokenizedBufferEnd + tokenizedBufferDelta) - end

    changeEvent = { start, end, screenDelta, bufferDelta }
    if bufferChange
      @pauseMarkerObservers()
      @pendingChangeEvent = changeEvent
    else
      @triggerChanged(changeEvent, false)

  handleMarkersUpdated: =>
    event = @pendingChangeEvent
    @pendingChangeEvent = null
    @triggerChanged(event, false)

  buildLineForBufferRow: (bufferRow) ->
    @buildLinesForBufferRows(bufferRow, bufferRow)

  buildLinesForBufferRows: (startBufferRow, endBufferRow) ->
    lineFragments = []
    startBufferColumn = null
    currentBufferRow = startBufferRow
    currentScreenLineLength = 0

    startBufferColumn = 0
    while currentBufferRow <= endBufferRow
      screenLine = @tokenizedBuffer.lineForScreenRow(currentBufferRow)

      if fold = @largestFoldStartingAtBufferRow(currentBufferRow)
        screenLine = screenLine.copy()
        screenLine.fold = fold
        screenLine.bufferRows = fold.getBufferRowCount()
        lineFragments.push(screenLine)
        currentBufferRow = fold.endRow + 1
        continue

      startBufferColumn ?= 0
      screenLine = screenLine.softWrapAt(startBufferColumn)[1] if startBufferColumn > 0
      wrapScreenColumn = @findWrapColumn(screenLine.text, @softWrapColumn)
      if wrapScreenColumn?
        screenLine = screenLine.softWrapAt(wrapScreenColumn)[0]
        screenLine.screenDelta = new Point(1, 0)
        startBufferColumn += wrapScreenColumn
      else
        currentBufferRow++
        startBufferColumn = 0

      lineFragments.push(screenLine)

    lineFragments

  ###
  # Public #
  ###

  # Public: Given a line, finds the point where it would wrap.
  #
  # line - The {String} to check
  # softWrapColumn - The {Number} where you want soft wrapping to occur
  #
  # Returns a {Number} representing the `line` position where the wrap would take place.
  # Returns `null` if a wrap wouldn't occur.
  findWrapColumn: (line, softWrapColumn) ->
    return unless line.length > softWrapColumn

    if /\s/.test(line[softWrapColumn])
      # search forward for the start of a word past the boundary
      for column in [softWrapColumn..line.length]
        return column if /\S/.test(line[column])
      return line.length
    else
      # search backward for the start of the word on the boundary
      for column in [softWrapColumn..0]
        return column + 1 if /\s/.test(line[column])
      return softWrapColumn

  # Public: Given a range in screen coordinates, this expands it to the start and end of a line
  #
  # screenRange - The {Range} to expand
  #
  # Returns a new {Range}.
  expandScreenRangeToLineEnds: (screenRange) ->
    screenRange = Range.fromObject(screenRange)
    { start, end } = screenRange
    new Range([start.row, 0], [end.row, @lineMap.lineForScreenRow(end.row).text.length])

  # Public: Given a range in buffer coordinates, this expands it to the start and end of a line
  #
  # screenRange - The {Range} to expand
  #
  # Returns a new {Range}.
  expandBufferRangeToLineEnds: (bufferRange) ->
    bufferRange = Range.fromObject(bufferRange)
    { start, end } = bufferRange
    new Range([start.row, 0], [end.row, Infinity])

  # Public: Calculates a {Range} representing the start of the {Buffer} until the end.
  #
  # Returns a {Range}.
  rangeForAllLines: ->
    new Range([0, 0], @clipScreenPosition([Infinity, Infinity]))

  # Public: Retrieves a {DisplayBufferMarker} based on its id.
  #
  # id - A {Number} representing a marker id
  #
  # Returns the {DisplayBufferMarker} (if it exists).
  getMarker: (id) ->
    @markers[id] ? new DisplayBufferMarker({id, displayBuffer: this})

  # Public: Retrieves the active markers in the buffer.
  #
  # Returns an {Array} of existing {DisplayBufferMarker}s.
  getMarkers: ->
    _.values(@markers)

  # Public: Constructs a new marker at the given screen range.
  #
  # range - The marker {Range} (representing the distance between the head and tail)
  # options - Options to pass to the {BufferMarker} constructor
  #
  # Returns a {Number} representing the new marker's ID.
  markScreenRange: (args...) ->
    bufferRange = @bufferRangeForScreenRange(args.shift())
    @markBufferRange(bufferRange, args...)

  # Public: Constructs a new marker at the given buffer range.
  #
  # range - The marker {Range} (representing the distance between the head and tail)
  # options - Options to pass to the {BufferMarker} constructor
  #
  # Returns a {Number} representing the new marker's ID.
  markBufferRange: (args...) ->
    @buffer.markRange(args...)

  # Public: Constructs a new marker at the given screen position.
  #
  # range - The marker {Range} (representing the distance between the head and tail)
  # options - Options to pass to the {BufferMarker} constructor
  #
  # Returns a {Number} representing the new marker's ID.
  markScreenPosition: (screenPosition, options) ->
    @markBufferPosition(@bufferPositionForScreenPosition(screenPosition), options)

  # Public: Constructs a new marker at the given buffer position.
  #
  # range - The marker {Range} (representing the distance between the head and tail)
  # options - Options to pass to the {BufferMarker} constructor
  #
  # Returns a {Number} representing the new marker's ID.
  markBufferPosition: (bufferPosition, options) ->
    @buffer.markPosition(bufferPosition, options)

  # Public: Removes the marker with the given id.
  #
  # id - The {Number} of the ID to remove
  destroyMarker: (id) ->
    @buffer.destroyMarker(id)
    delete @markers[id]

  # Public: Gets the screen range of the display marker.
  #
  # id - The {Number} of the ID to check
  #
  # Returns a {Range}.
  getMarkerScreenRange: (id) ->
    @getMarker(id).getScreenRange()

  # Public: Modifies the screen range of the display marker.
  #
  # id - The {Number} of the ID to change
  # screenRange - The new {Range} to use
  # options - A hash of options matching those found in {BufferMarker.setRange}
  setMarkerScreenRange: (id, screenRange, options) ->
    @getMarker(id).setScreenRange(screenRange, options)

  # Public: Gets the buffer range of the display marker.
  #
  # id - The {Number} of the ID to check
  #
  # Returns a {Range}.
  getMarkerBufferRange: (id) ->
    @getMarker(id).getBufferRange()

  # Public: Modifies the buffer range of the display marker.
  #
  # id - The {Number} of the ID to change
  # screenRange - The new {Range} to use
  # options - A hash of options matching those found in {BufferMarker.setRange}
  setMarkerBufferRange: (id, bufferRange, options) ->
    @getMarker(id).setBufferRange(bufferRange, options)

  # Public: Retrieves the screen position of the marker's head.
  #
  # id - The {Number} of the ID to check
  #
  # Returns a {Point}.
  getMarkerScreenPosition: (id) ->
    @getMarkerHeadScreenPosition(id)

  # Public: Retrieves the buffer position of the marker's head.
  #
  # id - The {Number} of the ID to check
  #
  # Returns a {Point}.
  getMarkerBufferPosition: (id) ->
    @getMarkerHeadBufferPosition(id)

  # Public: Retrieves the screen position of the marker's head.
  #
  # id - The {Number} of the ID to check
  #
  # Returns a {Point}.
  getMarkerHeadScreenPosition: (id) ->
    @getMarker(id).getHeadScreenPosition()

  # Public: Sets the screen position of the marker's head.
  #
  # id - The {Number} of the ID to change
  # screenRange - The new {Point} to use
  # options - A hash of options matching those found in {DisplayBuffer.bufferPositionForScreenPosition}
  setMarkerHeadScreenPosition: (id, screenPosition, options) ->
    @getMarker(id).setHeadScreenPosition(screenPosition, options)

  # Public: Retrieves the buffer position of the marker's head.
  #
  # id - The {Number} of the ID to check
  #
  # Returns a {Point}.
  getMarkerHeadBufferPosition: (id) ->
    @getMarker(id).getHeadBufferPosition()

  # Public: Sets the buffer position of the marker's head.
  #
  # id - The {Number} of the ID to check
  # screenRange - The new {Point} to use
  # options - A hash of options matching those found in {DisplayBuffer.bufferPositionForScreenPosition}
  setMarkerHeadBufferPosition: (id, bufferPosition) ->
    @getMarker(id).setHeadBufferPosition(bufferPosition)

  # Public: Retrieves the screen position of the marker's tail.
  #
  # id - The {Number} of the ID to check
  #
  # Returns a {Point}.
  getMarkerTailScreenPosition: (id) ->
    @getMarker(id).getTailScreenPosition()

  # Public: Sets the screen position of the marker's tail.
  #
  # id - The {Number} of the ID to change
  # screenRange - The new {Point} to use
  # options - A hash of options matching those found in {DisplayBuffer.bufferPositionForScreenPosition}
  setMarkerTailScreenPosition: (id, screenPosition, options) ->
    @getMarker(id).setTailScreenPosition(screenPosition, options)

  # Public: Retrieves the buffer position of the marker's tail.
  #
  # id - The {Number} of the ID to check
  #
  # Returns a {Point}.
  getMarkerTailBufferPosition: (id) ->
    @getMarker(id).getTailBufferPosition()

  # Public: Sets the buffer position of the marker's tail.
  #
  # id - The {Number} of the ID to check
  # screenRange - The new {Point} to use
  # options - A hash of options matching those found in {DisplayBuffer.bufferPositionForScreenPosition}
  setMarkerTailBufferPosition: (id, bufferPosition) ->
    @getMarker(id).setTailBufferPosition(bufferPosition)

  # Public: Sets the marker's tail to the same position as the marker's head.
  #
  # This only works if there isn't already a tail position.
  #
  # id - A {Number} representing the marker to change
  #
  # Returns a {Point} representing the new tail position.
  placeMarkerTail: (id) ->
    @getMarker(id).placeTail()

  # Public: Removes the tail from the marker.
  #
  # id - A {Number} representing the marker to change
  clearMarkerTail: (id) ->
    @getMarker(id).clearTail()

  # Public: Identifies if the ending position of a marker is greater than the starting position.
  #
  # This can happen when, for example, you highlight text "up" in a {Buffer}.
  #
  # id - A {Number} representing the marker to check
  #
  # Returns a {Boolean}.
  isMarkerReversed: (id) ->
    @buffer.isMarkerReversed(id)

  # Public: Identifies if the marker's head position is equal to its tail.
  #
  # id - A {Number} representing the marker to check
  #
  # Returns a {Boolean}.
  isMarkerRangeEmpty: (id) ->
    @buffer.isMarkerRangeEmpty(id)

  # Public: Sets a callback to be fired whenever a marker is changed.
  #
  # id - A {Number} representing the marker to watch
  # callback - A {Function} to execute
  observeMarker: (id, callback) ->
    @getMarker(id).observe(callback)

  ###
  # Internal #
  ###

  pauseMarkerObservers: ->
    marker.pauseEvents() for marker in @getMarkers()

  resumeMarkerObservers: ->
    marker.resumeEvents() for marker in @getMarkers()

  refreshMarkerScreenPositions: ->
    for marker in @getMarkers()
      marker.notifyObservers(bufferChanged: false)

  destroy: ->
    @tokenizedBuffer.destroy()
    @buffer.off 'markers-updated', @handleMarkersUpdated

  logLines: (start, end) ->
    @lineMap.logLines(start, end)

  getDebugSnapshot: ->
    lines = ["Display Buffer:"]
    for screenLine, row in @lineMap.linesForScreenRows(0, @getLastRow())
        lines.push "#{row}: #{screenLine.text}"
    lines.join('\n')

_.extend DisplayBuffer.prototype, EventEmitter
