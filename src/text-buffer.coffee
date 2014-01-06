_ = require 'underscore-plus'
diff = require 'diff'
Q = require 'q'
{P} = require 'scandal'
Serializable = require 'serializable'
TextBufferCore = require 'text-buffer'
{Point, Range} = TextBufferCore
{Subscriber, Emitter} = require 'emissary'

File = require './file'

# Private: Represents the contents of a file.
#
# The `TextBuffer` is often associated with a {File}. However, this is not always
# the case, as a `TextBuffer` could be an unsaved chunk of text.
module.exports =
class TextBuffer extends TextBufferCore
  atom.deserializers.add(this)

  Serializable.includeInto(this)
  Subscriber.includeInto(this)
  Emitter.includeInto(this)

  stoppedChangingDelay: 300
  stoppedChangingTimeout: null
  cachedDiskContents: null
  cachedMemoryContents: null
  conflict: false
  file: null
  refcount: 0

  constructor: ({filePath, @modifiedWhenLastPersisted, @digestWhenLastPersisted, loadWhenAttached}={}) ->
    super
    @loaded = false
    @modifiedWhenLastPersisted ?= false

    @useSerializedText = @modifiedWhenLastPersisted != false

    @subscribe this, 'changed', @handleTextChange

    @setPath(filePath)

    @load() if loadWhenAttached

  # Private:
  serializeParams: ->
    params = super
    _.extend params,
      filePath: @getPath()
      modifiedWhenLastPersisted: @isModified()
      digestWhenLastPersisted: @file?.getDigest()

  # Private:
  deserializeParams: (params) ->
    params = super(params)
    params.loadWhenAttached = true
    params

  loadSync: ->
    @updateCachedDiskContentsSync()
    @finishLoading()

  load: ->
    @updateCachedDiskContents().then => @finishLoading()

  finishLoading: ->
    if @isAlive()
      @loaded = true
      if @useSerializedText and @digestWhenLastPersisted is @file?.getDigest()
        @emitModifiedStatusChanged(true)
      else
        @reload()
      @clearUndoStack()
    this

  ### Internal ###

  handleTextChange: (event) =>
    @cachedMemoryContents = null
    @conflict = false if @conflict and !@isModified()
    @scheduleModifiedEvents()

  destroy: ->
    unless @destroyed
      @cancelStoppedChangingTimeout()
      @file?.off()
      @unsubscribe()
      @destroyed = true
      @emit 'destroyed'

  isAlive: -> not @destroyed

  isDestroyed: -> @destroyed

  isRetained: -> @refcount > 0

  retain: ->
    @refcount++
    this

  release: ->
    @refcount--
    @destroy() unless @isRetained()
    this

  subscribeToFile: ->
    @file.on "contents-changed", =>
      @conflict = true if @isModified()
      previousContents = @cachedDiskContents

      # Synchrounously update the disk contents because the {File} has already cached them. If the
      # contents updated asynchrounously multiple `conlict` events could trigger for the same disk
      # contents.
      @updateCachedDiskContentsSync()
      return if previousContents == @cachedDiskContents

      if @conflict
        @emit "contents-conflicted"
      else
        @reload()

    @file.on "removed", =>
      modified = @getText() != @cachedDiskContents
      @wasModifiedBeforeRemove = modified
      if modified
        @updateCachedDiskContents()
      else
        @destroy()

    @file.on "moved", =>
      @emit "path-changed", this

  ### Public ###

  # Identifies if the buffer belongs to multiple editors.
  #
  # For example, if the {EditorView} was split.
  #
  # Returns a {Boolean}.
  hasMultipleEditors: -> @refcount > 1

  # Reloads a file in the {Editor}.
  #
  # Sets the buffer's content to the cached disk contents
  reload: ->
    @emit 'will-reload'
    @setTextViaDiff(@cachedDiskContents)
    @emitModifiedStatusChanged(false)
    @emit 'reloaded'

  # Private: Rereads the contents of the file, and stores them in the cache.
  updateCachedDiskContentsSync: ->
    @cachedDiskContents = @file?.readSync() ? ""

  # Private: Rereads the contents of the file, and stores them in the cache.
  updateCachedDiskContents: ->
    Q(@file?.read() ? "").then (contents) =>
      @cachedDiskContents = contents

  # Gets the file's basename--that is, the file without any directory information.
  #
  # Returns a {String}.
  getBaseName: ->
    @file?.getBaseName()

  # Retrieves the path for the file.
  #
  # Returns a {String}.
  getPath: ->
    @file?.getPath()

  getUri: ->
    atom.project.relativize(@getPath())

  # Sets the path for the file.
  #
  # path - A {String} representing the new file path
  setPath: (path) ->
    return if path == @getPath()

    @file?.off()

    if path
      @file = new File(path)
      @subscribeToFile()
    else
      @file = null

    @emit "path-changed", this

  # Retrieves the current buffer's file extension.
  #
  # Returns a {String}.
  getExtension: ->
    if @getPath()
      @getPath().split('/').pop().split('.').pop()
    else
      null

  # Retrieves the cached buffer contents.
  #
  # Returns a {String}.
  getText: ->
    @cachedMemoryContents ?= @getTextInRange(@getRange())

  # Replaces the current buffer contents.
  #
  # text - A {String} containing the new buffer contents.
  setText: (text) ->
    @change(@getRange(), text, normalizeLineEndings: false)

  # Private: Replaces the current buffer contents. Only apply the differences.
  #
  # text - A {String} containing the new buffer contents.
  setTextViaDiff: (text) ->
    currentText = @getText()
    return if currentText == text

    endsWithNewline = (str) ->
      /[\r\n]+$/g.test(str)

    computeBufferColumn = (str) ->
      newlineIndex = Math.max(str.lastIndexOf('\n'), str.lastIndexOf('\r'))
      if endsWithNewline(str)
        0
      else if newlineIndex == -1
        str.length
      else
        str.length - newlineIndex - 1

    @transact =>
      row = 0
      column = 0
      currentPosition = [0, 0]

      lineDiff = diff.diffLines(currentText, text)
      changeOptions = normalizeLineEndings: false

      for change in lineDiff
        lineCount = change.value.match(/\n/g)?.length ? 0
        currentPosition[0] = row
        currentPosition[1] = column

        if change.added
          @change([currentPosition, currentPosition], change.value, changeOptions)
          row += lineCount
          column = computeBufferColumn(change.value)

        else if change.removed
          endRow = row + lineCount
          endColumn = column + computeBufferColumn(change.value)
          @change([currentPosition, [endRow, endColumn]], '', changeOptions)

        else
          row += lineCount
          column = computeBufferColumn(change.value)

  # Gets the range of the buffer contents.
  #
  # Returns a new {Range}, from `[0, 0]` to the end of the buffer.
  getRange: ->
    lastRow = @getLastRow()
    new Range([0, 0], [lastRow, @lineLengthForRow(lastRow)])

  suggestedLineEndingForRow: (row) ->
    if row is @getLastRow()
      @lineEndingForRow(row - 1)
    else
      @lineEndingForRow(row)

  # Given a row, returns the length of the line ending
  #
  # row - A {Number} indicating the row.
  #
  # Returns a {Number}.
  lineEndingLengthForRow: (row) ->
    (@lineEndingForRow(row) ? '').length

  # Given a buffer row, this retrieves the range for that line.
  #
  # row - A {Number} identifying the row
  # options - A hash with one key, `includeNewline`, which specifies whether you
  #           want to include the trailing newline
  #
  # Returns a {Range}.
  rangeForRow: (row, { includeNewline } = {}) ->
    if includeNewline and row < @getLastRow()
      new Range([row, 0], [row + 1, 0])
    else
      new Range([row, 0], [row, @lineLengthForRow(row)])

  # Finds the last line in the current buffer.
  #
  # Returns a {String}.
  getLastLine: ->
    @lineForRow(@getLastRow())

  # Finds the last point in the current buffer.
  #
  # Returns a {Point} representing the last position.
  getEofPosition: ->
    lastRow = @getLastRow()
    new Point(lastRow, @lineLengthForRow(lastRow))

  # Given a row, this deletes it from the buffer.
  #
  # row - A {Number} representing the row to delete
  deleteRow: (row) ->
    @deleteRows(row, row)

  # Deletes a range of rows from the buffer.
  #
  # start - A {Number} representing the starting row
  # end - A {Number} representing the ending row
  deleteRows: (start, end) ->
    startPoint = null
    endPoint = null
    if end == @getLastRow()
      if start > 0
        startPoint = [start - 1, @lineLengthForRow(start - 1)]
      else
        startPoint = [start, 0]
      endPoint = [end, @lineLengthForRow(end)]
    else
      startPoint = [start, 0]
      endPoint = [end + 1, 0]
    @delete(new Range(startPoint, endPoint))

  # Adds text to the end of the buffer.
  #
  # text - A {String} of text to add
  append: (text) ->
    @insert(@getEofPosition(), text)

  # Adds text to a specific point in the buffer
  #
  # position - A {Point} in the buffer to insert into
  # text - A {String} of text to add
  insert: (position, text) ->
    @change(new Range(position, position), text)

  # Deletes text from the buffer
  #
  # range - A {Range} whose text to delete
  delete: (range) ->
    @change(range, '')

  # Saves the buffer.
  save: ->
    @saveAs(@getPath()) if @isModified()

  # Saves the buffer at a specific path.
  #
  # path - The path to save at.
  saveAs: (path) ->
    unless path then throw new Error("Can't save buffer with no file path")

    @emit 'will-be-saved', this
    @setPath(path)
    @cachedDiskContents = @getText()
    @file.write(@getText())
    @emitModifiedStatusChanged(false)
    @emit 'saved', this

  # Identifies if the buffer was modified.
  #
  # Returns a {Boolean}.
  isModified: ->
    return false unless @loaded
    if @file
      if @file.exists()
        @getText() != @cachedDiskContents
      else
        @wasModifiedBeforeRemove ? not @isEmpty()
    else
      not @isEmpty()

  # Identifies if a buffer is in a git conflict with `HEAD`.
  #
  # Returns a {Boolean}.
  isInConflict: -> @conflict

  destroyMarker: (id) ->
    @getMarker(id)?.destroy()

  # Retrieves the quantity of markers in a buffer.
  #
  # Returns a {Number}.
  getMarkerCount: ->
    @getMarkers().length

  # Identifies if a character sequence is within a certain range.
  #
  # regex - The {RegExp} to check
  # startIndex - The starting row {Number}
  # endIndex - The ending row {Number}
  #
  # Returns an {Array} of {RegExp}s, representing the matches.
  matchesInCharacterRange: (regex, startIndex, endIndex) ->
    text = @getText()
    matches = []

    regex.lastIndex = startIndex
    while match = regex.exec(text)
      matchLength = match[0].length
      matchStartIndex = match.index
      matchEndIndex = matchStartIndex + matchLength

      if matchEndIndex > endIndex
        regex.lastIndex = 0
        if matchStartIndex < endIndex and submatch = regex.exec(text[matchStartIndex...endIndex])
          submatch.index = matchStartIndex
          matches.push submatch
        break

      matchEndIndex++ if matchLength is 0
      regex.lastIndex = matchEndIndex
      matches.push match

    matches

  # Scans for text in the buffer, calling a function on each match.
  #
  # regex - A {RegExp} representing the text to find
  # iterator - A {Function} that's called on each match
  scan: (regex, iterator) ->
    @scanInRange regex, @getRange(), (result) =>
      result.lineText = @lineForRow(result.range.start.row)
      result.lineTextOffset = 0
      iterator(result)

  # Replace all matches of regex with replacementText
  #
  # regex: A {RegExp} representing the text to find
  # replacementText: A {String} representing the text to replace
  #
  # Returns the number of replacements made
  replace: (regex, replacementText) ->
    doSave = !@isModified()
    replacements = 0

    @transact =>
      @scan regex, ({matchText, replace}) ->
        replace(matchText.replace(regex, replacementText))
        replacements++

    @save() if doSave

    replacements

  # Scans for text in a given range, calling a function on each match.
  #
  # regex - A {RegExp} representing the text to find
  # range - A {Range} in the buffer to search within
  # iterator - A {Function} that's called on each match
  # reverse - A {Boolean} indicating if the search should be backwards (default: `false`)
  scanInRange: (regex, range, iterator, reverse=false) ->
    range = @clipRange(range)
    global = regex.global
    flags = "gm"
    flags += "i" if regex.ignoreCase
    regex = new RegExp(regex.source, flags)

    startIndex = @characterIndexForPosition(range.start)
    endIndex = @characterIndexForPosition(range.end)

    matches = @matchesInCharacterRange(regex, startIndex, endIndex)
    lengthDelta = 0

    keepLooping = null
    replacementText = null
    stop = -> keepLooping = false
    replace = (text) -> replacementText = text

    matches.reverse() if reverse
    for match in matches
      matchLength = match[0].length
      matchStartIndex = match.index
      matchEndIndex = matchStartIndex + matchLength

      startPosition = @positionForCharacterIndex(matchStartIndex + lengthDelta)
      endPosition = @positionForCharacterIndex(matchEndIndex + lengthDelta)
      range = new Range(startPosition, endPosition)
      keepLooping = true
      replacementText = null
      matchText = match[0]
      iterator({ match, matchText, range, stop, replace })

      if replacementText?
        @change(range, replacementText)
        lengthDelta += replacementText.length - matchLength unless reverse

      break unless global and keepLooping

  # Scans for text in a given range _backwards_, calling a function on each match.
  #
  # regex - A {RegExp} representing the text to find
  # range - A {Range} in the buffer to search within
  # iterator - A {Function} that's called on each match
  backwardsScanInRange: (regex, range, iterator) ->
    @scanInRange regex, range, iterator, true

  # Given a row, identifies if it is blank.
  #
  # row - A row {Number} to check
  #
  # Returns a {Boolean}.
  isRowBlank: (row) ->
    not /\S/.test @lineForRow(row)

  # Given a row, this finds the next row above it that's empty.
  #
  # startRow - A {Number} identifying the row to start checking at
  #
  # Returns the row {Number} of the first blank row.
  # Returns `null` if there's no other blank row.
  previousNonBlankRow: (startRow) ->
    return null if startRow == 0

    startRow = Math.min(startRow, @getLastRow())
    for row in [(startRow - 1)..0]
      return row unless @isRowBlank(row)
    null

  # Given a row, this finds the next row that's blank.
  #
  # startRow - A row {Number} to check
  #
  # Returns the row {Number} of the next blank row.
  # Returns `null` if there's no other blank row.
  nextNonBlankRow: (startRow) ->
    lastRow = @getLastRow()
    if startRow < lastRow
      for row in [(startRow + 1)..lastRow]
        return row unless @isRowBlank(row)
    null

  # Identifies if the buffer has soft tabs anywhere.
  #
  # Returns a {Boolean},
  usesSoftTabs: ->
    for row in [0..@getLastRow()]
      if match = @lineForRow(row).match(/^\s/)
        return match[0][0] != '\t'
    undefined

  ### Internal ###

  change: (oldRange, newText, options={}) ->
    oldRange = @clipRange(oldRange)
    newText = @normalizeLineEndings(oldRange.start.row, newText) if options.normalizeLineEndings ? true
    @setTextInRange(oldRange, newText, options)

  normalizeLineEndings: (startRow, text) ->
    if lineEnding = @suggestedLineEndingForRow(startRow)
      text.replace(/\r?\n/g, lineEnding)
    else
      text

  cancelStoppedChangingTimeout: ->
    clearTimeout(@stoppedChangingTimeout) if @stoppedChangingTimeout

  scheduleModifiedEvents: ->
    @cancelStoppedChangingTimeout()
    stoppedChangingCallback = =>
      @stoppedChangingTimeout = null
      modifiedStatus = @isModified()
      @emit 'contents-modified', modifiedStatus
      @emitModifiedStatusChanged(modifiedStatus)
    @stoppedChangingTimeout = setTimeout(stoppedChangingCallback, @stoppedChangingDelay)

  emitModifiedStatusChanged: (modifiedStatus) ->
    return if modifiedStatus is @previousModifiedStatus
    @previousModifiedStatus = modifiedStatus
    @emit 'modified-status-changed', modifiedStatus

  logLines: (start=0, end=@getLastRow())->
    for row in [start..end]
      line = @lineForRow(row)
      console.log row, line, line.length
