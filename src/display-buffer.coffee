_ = require 'underscore-plus'
{Emitter} = require 'emissary'
guid = require 'guid'
Serializable = require 'serializable'
{Model} = require 'theorist'
{Point, Range} = require 'text-buffer'
TokenizedBuffer = require './tokenized-buffer'
RowMap = require './row-map'
Fold = require './fold'
Token = require './token'
DisplayBufferMarker = require './display-buffer-marker'

class BufferToScreenConversionError extends Error
  constructor: (@message, @metadata) ->
    super
    Error.captureStackTrace(this, BufferToScreenConversionError)

module.exports =
class DisplayBuffer extends Model
  Serializable.includeInto(this)

  @properties
    softWrap: null
    editorWidthInChars: null

  constructor: ({tabLength, @editorWidthInChars, @tokenizedBuffer, buffer}={}) ->
    super
    @softWrap ?= atom.config.get('editor.softWrap') ? false
    @tokenizedBuffer ?= new TokenizedBuffer({tabLength, buffer})
    @buffer = @tokenizedBuffer.buffer
    @markers = {}
    @foldsByMarkerId = {}
    @updateAllScreenLines()
    @createFoldForMarker(marker) for marker in @buffer.findMarkers(@getFoldMarkerAttributes())
    @subscribe @tokenizedBuffer, 'grammar-changed', (grammar) => @emit 'grammar-changed', grammar
    @subscribe @tokenizedBuffer, 'changed', @handleTokenizedBufferChange
    @subscribe @buffer, 'markers-updated', @handleBufferMarkersUpdated
    @subscribe @buffer, 'marker-created', @handleBufferMarkerCreated

    @subscribe @$softWrap, (softWrap) =>
      @emit 'soft-wrap-changed', softWrap
      @updateWrappedScreenLines()

    @subscribe atom.config.observe 'editor.preferredLineLength', callNow: false, =>
      @updateWrappedScreenLines() if @softWrap and atom.config.get('editor.softWrapAtPreferredLineLength')

    @subscribe atom.config.observe 'editor.softWrapAtPreferredLineLength', callNow: false, =>
      @updateWrappedScreenLines() if @softWrap

  serializeParams: ->
    id: @id
    softWrap: @softWrap
    editorWidthInChars: @editorWidthInChars
    tokenizedBuffer: @tokenizedBuffer.serialize()

  deserializeParams: (params) ->
    params.tokenizedBuffer = TokenizedBuffer.deserialize(params.tokenizedBuffer)
    params

  copy: ->
    newDisplayBuffer = new DisplayBuffer({@buffer, tabLength: @getTabLength()})
    for marker in @findMarkers(displayBufferId: @id)
      marker.copy(displayBufferId: newDisplayBuffer.id)
    newDisplayBuffer

  updateAllScreenLines: ->
    @maxLineLength = 0
    @screenLines = []
    @rowMap = new RowMap
    @updateScreenLines(0, @buffer.getLineCount(), null, suppressChangeEvent: true)

  emitChanged: (eventProperties, refreshMarkers=true) ->
    if refreshMarkers
      @pauseMarkerObservers()
      @refreshMarkerScreenPositions()
    @emit 'changed', eventProperties
    @resumeMarkerObservers()

  updateWrappedScreenLines: ->
    start = 0
    end = @getLastRow()
    @updateAllScreenLines()
    screenDelta = @getLastRow() - end
    bufferDelta = 0
    @emitChanged({ start, end, screenDelta, bufferDelta })

  # Sets the visibility of the tokenized buffer.
  #
  # visible - A {Boolean} indicating of the tokenized buffer is shown
  setVisible: (visible) -> @tokenizedBuffer.setVisible(visible)

  # Deprecated: Use the softWrap property directly
  setSoftWrap: (@softWrap) -> @softWrap

  # Deprecated: Use the softWrap property directly
  getSoftWrap: -> @softWrap

  # Set the number of characters that fit horizontally in the editor.
  #
  # editorWidthInChars - A {Number} of characters.
  setEditorWidthInChars: (editorWidthInChars) ->
    previousWidthInChars = @editorWidthInChars
    @editorWidthInChars = editorWidthInChars
    if editorWidthInChars isnt previousWidthInChars and @softWrap
      @updateWrappedScreenLines()

  getSoftWrapColumn: ->
    if atom.config.get('editor.softWrapAtPreferredLineLength')
      Math.min(@editorWidthInChars, atom.config.getPositiveInt('editor.preferredLineLength', @editorWidthInChars))
    else
      @editorWidthInChars

  # Gets the screen line for the given screen row.
  #
  # screenRow - A {Number} indicating the screen row.
  #
  # Returns a {ScreenLine}.
  lineForRow: (row) ->
    @screenLines[row]

  # Gets the screen lines for the given screen row range.
  #
  # startRow - A {Number} indicating the beginning screen row.
  # endRow - A {Number} indicating the ending screen row.
  #
  # Returns an {Array} of {ScreenLine}s.
  linesForRows: (startRow, endRow) ->
    @screenLines[startRow..endRow]

  # Gets all the screen lines.
  #
  # Returns an {Array} of {ScreenLines}s.
  getLines: ->
    new Array(@screenLines...)

  # Given starting and ending screen rows, this returns an array of the
  # buffer rows corresponding to every screen row in the range
  #
  # startScreenRow - The screen row {Number} to start at
  # endScreenRow - The screen row {Number} to end at (default: the last screen row)
  #
  # Returns an {Array} of buffer rows as {Numbers}s.
  bufferRowsForScreenRows: (startScreenRow, endScreenRow) ->
    for screenRow in [startScreenRow..endScreenRow]
      @rowMap.bufferRowRangeForScreenRow(screenRow)[0]

  # Creates a new fold between two row numbers.
  #
  # startRow - The row {Number} to start folding at
  # endRow - The row {Number} to end the fold
  #
  # Returns the new {Fold}.
  createFold: (startRow, endRow) ->
    foldMarker =
      @findFoldMarker({startRow, endRow}) ?
        @buffer.markRange([[startRow, 0], [endRow, Infinity]], @getFoldMarkerAttributes())
    @foldForMarker(foldMarker)

  isFoldedAtBufferRow: (bufferRow) ->
    @largestFoldContainingBufferRow(bufferRow)?

  isFoldedAtScreenRow: (screenRow) ->
    @largestFoldContainingBufferRow(@bufferRowForScreenRow(screenRow))?

  # Destroys the fold with the given id
  destroyFoldWithId: (id) ->
    @foldsByMarkerId[id]?.destroy()

  # Removes any folds found that contain the given buffer row.
  #
  # bufferRow - The buffer row {Number} to check against
  destroyFoldsContainingBufferRow: (bufferRow) ->
    fold.destroy() for fold in @foldsContainingBufferRow(bufferRow)

  # Given a buffer row, this returns the largest fold that starts there.
  #
  # Largest is defined as the fold whose difference between its start and end points
  # are the greatest.
  #
  # bufferRow - A {Number} indicating the buffer row
  #
  # Returns a {Fold} or null if none exists.
  largestFoldStartingAtBufferRow: (bufferRow) ->
    @foldsStartingAtBufferRow(bufferRow)[0]

  # Public: Given a buffer row, this returns all folds that start there.
  #
  # bufferRow - A {Number} indicating the buffer row
  #
  # Returns an {Array} of {Fold}s.
  foldsStartingAtBufferRow: (bufferRow) ->
    for marker in @findFoldMarkers(startRow: bufferRow)
      @foldForMarker(marker)

  # Given a screen row, this returns the largest fold that starts there.
  #
  # Largest is defined as the fold whose difference between its start and end points
  # are the greatest.
  #
  # screenRow - A {Number} indicating the screen row
  #
  # Returns a {Fold}.
  largestFoldStartingAtScreenRow: (screenRow) ->
    @largestFoldStartingAtBufferRow(@bufferRowForScreenRow(screenRow))

  # Given a buffer row, this returns the largest fold that includes it.
  #
  # Largest is defined as the fold whose difference between its start and end rows
  # is the greatest.
  #
  # bufferRow - A {Number} indicating the buffer row
  #
  # Returns a {Fold}.
  largestFoldContainingBufferRow: (bufferRow) ->
    @foldsContainingBufferRow(bufferRow)[0]

  # Public: Given a buffer row, this returns folds that include it.
  #
  #
  # bufferRow - A {Number} indicating the buffer row
  #
  # Returns an {Array} of {Fold}s.
  foldsContainingBufferRow: (bufferRow) ->
    for marker in @findFoldMarkers(intersectsRow: bufferRow)
      @foldForMarker(marker)

  # Given a buffer row, this converts it into a screen row.
  #
  # bufferRow - A {Number} representing a buffer row
  #
  # Returns a {Number}.
  screenRowForBufferRow: (bufferRow) ->
    @rowMap.screenRowRangeForBufferRow(bufferRow)[0]

  lastScreenRowForBufferRow: (bufferRow) ->
    @rowMap.screenRowRangeForBufferRow(bufferRow)[1] - 1

  # Given a screen row, this converts it into a buffer row.
  #
  # screenRow - A {Number} representing a screen row
  #
  # Returns a {Number}.
  bufferRowForScreenRow: (screenRow) ->
    @rowMap.bufferRowRangeForScreenRow(screenRow)[0]

  # Given a buffer range, this converts it into a screen position.
  #
  # bufferRange - The {Range} to convert
  #
  # Returns a {Range}.
  screenRangeForBufferRange: (bufferRange) ->
    bufferRange = Range.fromObject(bufferRange)
    start = @screenPositionForBufferPosition(bufferRange.start)
    end = @screenPositionForBufferPosition(bufferRange.end)
    new Range(start, end)

  # Given a screen range, this converts it into a buffer position.
  #
  # screenRange - The {Range} to convert
  #
  # Returns a {Range}.
  bufferRangeForScreenRange: (screenRange) ->
    screenRange = Range.fromObject(screenRange)
    start = @bufferPositionForScreenPosition(screenRange.start)
    end = @bufferPositionForScreenPosition(screenRange.end)
    new Range(start, end)

  # Gets the number of screen lines.
  #
  # Returns a {Number}.
  getLineCount: ->
    @screenLines.length

  # Gets the number of the last screen line.
  #
  # Returns a {Number}.
  getLastRow: ->
    @getLineCount() - 1

  # Gets the length of the longest screen line.
  #
  # Returns a {Number}.
  getMaxLineLength: ->
    @maxLineLength

  # Given a buffer position, this converts it into a screen position.
  #
  # bufferPosition - An object that represents a buffer position. It can be either
  #                  an {Object} (`{row, column}`), {Array} (`[row, column]`), or {Point}
  # options - A hash of options with the following keys:
  #           wrapBeyondNewlines:
  #           wrapAtSoftNewlines:
  #
  # Returns a {Point}.
  screenPositionForBufferPosition: (bufferPosition, options) ->
    { row, column } = @buffer.clipPosition(bufferPosition)
    [startScreenRow, endScreenRow] = @rowMap.screenRowRangeForBufferRow(row)
    for screenRow in [startScreenRow...endScreenRow]
      screenLine = @screenLines[screenRow]

      unless screenLine?
        throw new BufferToScreenConversionError "No screen line exists when converting buffer row to screen row",
          softWrapEnabled: @getSoftWrap()
          foldCount: @findFoldMarkers().length
          lastBufferRow: @buffer.getLastRow()
          lastScreenRow: @getLastRow()

      maxBufferColumn = screenLine.getMaxBufferColumn()
      if screenLine.isSoftWrapped() and column > maxBufferColumn
        continue
      else
        if column <= maxBufferColumn
          screenColumn = screenLine.screenColumnForBufferColumn(column)
        else
          screenColumn = Infinity
        break

    @clipScreenPosition([screenRow, screenColumn], options)

  # Given a buffer position, this converts it into a screen position.
  #
  # screenPosition - An object that represents a buffer position. It can be either
  #                  an {Object} (`{row, column}`), {Array} (`[row, column]`), or {Point}
  # options - A hash of options with the following keys:
  #           wrapBeyondNewlines:
  #           wrapAtSoftNewlines:
  #
  # Returns a {Point}.
  bufferPositionForScreenPosition: (screenPosition, options) ->
    { row, column } = @clipScreenPosition(Point.fromObject(screenPosition), options)
    [bufferRow] = @rowMap.bufferRowRangeForScreenRow(row)
    new Point(bufferRow, @screenLines[row].bufferColumnForScreenColumn(column))

  # Retrieves the grammar's token scopes for a buffer position.
  #
  # bufferPosition - A {Point} in the {TextBuffer}
  #
  # Returns an {Array} of {String}s.
  scopesForBufferPosition: (bufferPosition) ->
    @tokenizedBuffer.scopesForPosition(bufferPosition)

  bufferRangeForScopeAtPosition: (selector, position) ->
    @tokenizedBuffer.bufferRangeForScopeAtPosition(selector, position)

  # Retrieves the grammar's token for a buffer position.
  #
  # bufferPosition - A {Point} in the {TextBuffer}.
  #
  # Returns a {Token}.
  tokenForBufferPosition: (bufferPosition) ->
    @tokenizedBuffer.tokenForPosition(bufferPosition)

  # Retrieves the current tab length.
  #
  # Returns a {Number}.
  getTabLength: ->
    @tokenizedBuffer.getTabLength()

  # Specifies the tab length.
  #
  # tabLength - A {Number} that defines the new tab length.
  setTabLength: (tabLength) ->
    @tokenizedBuffer.setTabLength(tabLength)

  # Get the grammar for this buffer.
  #
  # Returns the current {Grammar} or the {NullGrammar}.
  getGrammar: ->
    @tokenizedBuffer.grammar

  # Sets the grammar for the buffer.
  #
  # grammar - Sets the new grammar rules
  setGrammar: (grammar) ->
    @tokenizedBuffer.setGrammar(grammar)

  # Reloads the current grammar.
  reloadGrammar: ->
    @tokenizedBuffer.reloadGrammar()

  # Given a position, this clips it to a real position.
  #
  # For example, if `position`'s row exceeds the row count of the buffer,
  # or if its column goes beyond a line's length, this "sanitizes" the value
  # to a real position.
  #
  # position - The {Point} to clip
  # options - A hash with the following values:
  #           wrapBeyondNewlines: if `true`, continues wrapping past newlines
  #           wrapAtSoftNewlines: if `true`, continues wrapping past soft newlines
  #           screenLine: if `true`, indicates that you're using a line number, not a row number
  #
  # Returns the new, clipped {Point}. Note that this could be the same as `position` if no clipping was performed.
  clipScreenPosition: (screenPosition, options={}) ->
    { wrapBeyondNewlines, wrapAtSoftNewlines } = options
    { row, column } = Point.fromObject(screenPosition)

    if row < 0
      row = 0
      column = 0
    else if row > @getLastRow()
      row = @getLastRow()
      column = Infinity
    else if column < 0
      column = 0

    screenLine = @screenLines[row]
    maxScreenColumn = screenLine.getMaxScreenColumn()

    if screenLine.isSoftWrapped() and column >= maxScreenColumn
      if wrapAtSoftNewlines
        row++
        column = 0
      else
        column = screenLine.clipScreenColumn(maxScreenColumn - 1)
    else if wrapBeyondNewlines and column > maxScreenColumn and row < @getLastRow()
      row++
      column = 0
    else
      column = screenLine.clipScreenColumn(column, options)
    new Point(row, column)

  # Given a line, finds the point where it would wrap.
  #
  # line - The {String} to check
  # softWrapColumn - The {Number} where you want soft wrapping to occur
  #
  # Returns a {Number} representing the `line` position where the wrap would take place.
  # Returns `null` if a wrap wouldn't occur.
  findWrapColumn: (line, softWrapColumn=@getSoftWrapColumn()) ->
    return unless @softWrap
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

  # Calculates a {Range} representing the start of the {TextBuffer} until the end.
  #
  # Returns a {Range}.
  rangeForAllLines: ->
    new Range([0, 0], @clipScreenPosition([Infinity, Infinity]))

  # Retrieves a {DisplayBufferMarker} based on its id.
  #
  # id - A {Number} representing a marker id
  #
  # Returns the {DisplayBufferMarker} (if it exists).
  getMarker: (id) ->
    unless marker = @markers[id]
      if bufferMarker = @buffer.getMarker(id)
        marker = new DisplayBufferMarker({bufferMarker, displayBuffer: this})
        @markers[id] = marker
    marker

  # Retrieves the active markers in the buffer.
  #
  # Returns an {Array} of existing {DisplayBufferMarker}s.
  getMarkers: ->
    @buffer.getMarkers().map ({id}) => @getMarker(id)

  getMarkerCount: ->
    @buffer.getMarkerCount()

  # Public: Constructs a new marker at the given screen range.
  #
  # range - The marker {Range} (representing the distance between the head and tail)
  # options - Options to pass to the {Marker} constructor
  #
  # Returns a {Number} representing the new marker's ID.
  markScreenRange: (args...) ->
    bufferRange = @bufferRangeForScreenRange(args.shift())
    @markBufferRange(bufferRange, args...)

  # Public: Constructs a new marker at the given buffer range.
  #
  # range - The marker {Range} (representing the distance between the head and tail)
  # options - Options to pass to the {Marker} constructor
  #
  # Returns a {Number} representing the new marker's ID.
  markBufferRange: (args...) ->
    @getMarker(@buffer.markRange(args...).id)

  # Public: Constructs a new marker at the given screen position.
  #
  # range - The marker {Range} (representing the distance between the head and tail)
  # options - Options to pass to the {Marker} constructor
  #
  # Returns a {Number} representing the new marker's ID.
  markScreenPosition: (screenPosition, options) ->
    @markBufferPosition(@bufferPositionForScreenPosition(screenPosition), options)

  # Public: Constructs a new marker at the given buffer position.
  #
  # range - The marker {Range} (representing the distance between the head and tail)
  # options - Options to pass to the {Marker} constructor
  #
  # Returns a {Number} representing the new marker's ID.
  markBufferPosition: (bufferPosition, options) ->
    @getMarker(@buffer.markPosition(bufferPosition, options).id)

  # Public: Removes the marker with the given id.
  #
  # id - The {Number} of the ID to remove
  destroyMarker: (id) ->
    @buffer.destroyMarker(id)
    delete @markers[id]

  # Finds the first marker satisfying the given attributes
  #
  # Refer to {DisplayBuffer::findMarkers} for details.
  #
  # Returns a {DisplayBufferMarker} or null
  findMarker: (attributes) ->
    @findMarkers(attributes)[0]

  # Finds all valid markers satisfying the given attributes
  #
  # attributes - The attributes against which to compare the markers' attributes
  #   There are some reserved keys that match against derived marker properties:
  #   startBufferRow - The buffer row at which the marker starts
  #   endBufferRow - The buffer row at which the marker ends
  #
  # Returns an {Array} of {DisplayBufferMarker}s
  findMarkers: (attributes) ->
    attributes = @translateToBufferMarkerAttributes(attributes)
    @buffer.findMarkers(attributes).map (stringMarker) => @getMarker(stringMarker.id)

  translateToBufferMarkerAttributes: (attributes) ->
    stringMarkerAttributes = {}
    for key, value of attributes
      switch key
        when 'startBufferRow'
          key = 'startRow'
        when 'endBufferRow'
          key = 'endRow'
        when 'containsBufferRange'
          key = 'containsRange'
        when 'containsBufferPosition'
          key = 'containsPosition'
      stringMarkerAttributes[key] = value
    stringMarkerAttributes

  findFoldMarker: (attributes) ->
    @findFoldMarkers(attributes)[0]

  findFoldMarkers: (attributes) ->
    @buffer.findMarkers(@getFoldMarkerAttributes(attributes))

  getFoldMarkerAttributes: (attributes={}) ->
    _.extend(attributes, class: 'fold', displayBufferId: @id)

  pauseMarkerObservers: ->
    marker.pauseEvents() for marker in @getMarkers()

  resumeMarkerObservers: ->
    marker.resumeEvents() for marker in @getMarkers()
    @emit 'markers-updated'

  refreshMarkerScreenPositions: ->
    for marker in @getMarkers()
      marker.notifyObservers(textChanged: false)

  destroy: ->
    marker.unsubscribe() for marker in @getMarkers()
    @tokenizedBuffer.destroy()
    @unsubscribe()

  logLines: (start=0, end=@getLastRow())->
    for row in [start..end]
      line = @lineForRow(row).text
      console.log row, @bufferRowForScreenRow(row), line, line.length

  handleTokenizedBufferChange: (tokenizedBufferChange) =>
    {start, end, delta, bufferChange} = tokenizedBufferChange
    @updateScreenLines(start, end + 1, delta, delayChangeEvent: bufferChange?)

  updateScreenLines: (startBufferRow, endBufferRow, bufferDelta=0, options={}) ->
    startBufferRow = @rowMap.bufferRowRangeForBufferRow(startBufferRow)[0]
    startScreenRow = @rowMap.screenRowRangeForBufferRow(startBufferRow)[0]
    endScreenRow = @rowMap.screenRowRangeForBufferRow(endBufferRow - 1)[1]

    {screenLines, regions} = @buildScreenLines(startBufferRow, endBufferRow + bufferDelta)
    @screenLines[startScreenRow...endScreenRow] = screenLines
    @rowMap.spliceRegions(startBufferRow, endBufferRow - startBufferRow, regions)
    @findMaxLineLength(startScreenRow, endScreenRow, screenLines)

    return if options.suppressChangeEvent

    changeEvent =
      start: startScreenRow
      end: endScreenRow - 1
      screenDelta: screenLines.length - (endScreenRow - startScreenRow)
      bufferDelta: bufferDelta

    if options.delayChangeEvent
      @pauseMarkerObservers()
      @pendingChangeEvent = changeEvent
    else
      @emitChanged(changeEvent, options.refreshMarkers)

  buildScreenLines: (startBufferRow, endBufferRow) ->
    screenLines = []
    regions = []
    rectangularRegion = null

    bufferRow = startBufferRow
    while bufferRow < endBufferRow
      tokenizedLine = @tokenizedBuffer.lineForScreenRow(bufferRow)

      if fold = @largestFoldStartingAtBufferRow(bufferRow)
        foldLine = tokenizedLine.copy()
        foldLine.fold = fold
        screenLines.push(foldLine)

        if rectangularRegion?
          regions.push(rectangularRegion)
          rectangularRegion = null

        foldedRowCount = fold.getBufferRowCount()
        regions.push(bufferRows: foldedRowCount, screenRows: 1)
        bufferRow += foldedRowCount
      else
        softWraps = 0
        while wrapScreenColumn = @findWrapColumn(tokenizedLine.text)
          [wrappedLine, tokenizedLine] = tokenizedLine.softWrapAt(wrapScreenColumn)
          screenLines.push(wrappedLine)
          softWraps++
        screenLines.push(tokenizedLine)

        if softWraps > 0
          if rectangularRegion?
            regions.push(rectangularRegion)
            rectangularRegion = null
          regions.push(bufferRows: 1, screenRows: softWraps + 1)
        else
          rectangularRegion ?= {bufferRows: 0, screenRows: 0}
          rectangularRegion.bufferRows++
          rectangularRegion.screenRows++

        bufferRow++

    if rectangularRegion?
      regions.push(rectangularRegion)

    {screenLines, regions}

  findMaxLineLength: (startScreenRow, endScreenRow, newScreenLines) ->
    if startScreenRow <= @longestScreenRow < endScreenRow
      @longestScreenRow = 0
      @maxLineLength = 0
      maxLengthCandidatesStartRow = 0
      maxLengthCandidates = @screenLines
    else
      maxLengthCandidatesStartRow = startScreenRow
      maxLengthCandidates = newScreenLines

    for screenLine, screenRow in maxLengthCandidates
      length = screenLine.text.length
      if length > @maxLineLength
        @longestScreenRow = maxLengthCandidatesStartRow + screenRow
        @maxLineLength = length

  handleBufferMarkersUpdated: =>
    if event = @pendingChangeEvent
      @pendingChangeEvent = null
      @emitChanged(event, false)

  handleBufferMarkerCreated: (marker) =>
    @createFoldForMarker(marker) if marker.matchesAttributes(@getFoldMarkerAttributes())
    @emit 'marker-created', @getMarker(marker.id)

  createFoldForMarker: (marker) ->
    new Fold(this, marker)

  foldForMarker: (marker) ->
    @foldsByMarkerId[marker.id]
