{Point} = require 'text-buffer'

module.exports =
class FakeLinesYardstick
  constructor: (@model, @presenter) ->
    @characterWidthsByScope = {}

  prepareScreenRowsForMeasurement: ->
    @presenter.getPreMeasurementState()
    @screenRows = new Set(@presenter.getScreenRows())

  getScopedCharacterWidth: (scopeNames, char) ->
    @getScopedCharacterWidths(scopeNames)[char]

  getScopedCharacterWidths: (scopeNames) ->
    scope = @characterWidthsByScope
    for scopeName in scopeNames
      scope[scopeName] ?= {}
      scope = scope[scopeName]
    scope.characterWidths ?= {}
    scope.characterWidths

  setScopedCharacterWidth: (scopeNames, character, width) ->
    @getScopedCharacterWidths(scopeNames)[character] = width

  pixelPositionForScreenPosition: (screenPosition, clip=true) ->
    screenPosition = Point.fromObject(screenPosition)
    screenPosition = @model.clipScreenPosition(screenPosition) if clip

    targetRow = screenPosition.row
    targetColumn = screenPosition.column
    baseCharacterWidth = @model.getDefaultCharWidth()

    top = @topPixelPositionForRow(targetRow)
    left = 0
    column = 0

    return {top, left: 0} unless @screenRows.has(screenPosition.row)

    iterator = @model.tokenizedLineForScreenRow(targetRow).getTokenIterator()
    while iterator.next()
      characterWidths = @getScopedCharacterWidths(iterator.getScopes())

      valueIndex = 0
      text = iterator.getText()
      while valueIndex < text.length
        if iterator.isPairedCharacter()
          char = text
          charLength = 2
          valueIndex += 2
        else
          char = text[valueIndex]
          charLength = 1
          valueIndex++

        break if column is targetColumn

        left += characterWidths[char] ? baseCharacterWidth unless char is '\0'
        column += charLength

    {top, left}

  rowForTopPixelPosition: (position, floor = true) ->
    top = 0
    for tileStartRow in [0..@model.getScreenLineCount()] by @presenter.getTileSize()
      tileEndRow = Math.min(tileStartRow + @presenter.getTileSize(), @model.getScreenLineCount())
      for row in [tileStartRow...tileEndRow] by 1
        nextTop = top + @presenter.getScreenRowHeight(row)
        if floor
          return row if nextTop > position
        else
          return row if top >= position
        top = nextTop
    @model.getScreenLineCount()

  topPixelPositionForRow: (targetRow) ->
    top = 0
    for row in [0..targetRow]
      return top if targetRow is row
      top += @presenter.getScreenRowHeight(row)
    top

  topPixelPositionForRows: (startRow, endRow, step) ->
    results = {}
    top = 0
    for tileStartRow in [0..endRow] by step
      tileEndRow = Math.min(tileStartRow + step, @model.getScreenLineCount())
      results[tileStartRow] = top
      for row in [tileStartRow...tileEndRow] by 1
        top += @presenter.getScreenRowHeight(row)
    results

  pixelRectForScreenRange: (screenRange) ->
    if screenRange.end.row > screenRange.start.row
      top = @pixelPositionForScreenPosition(screenRange.start).top
      left = 0
      height = @topPixelPositionForRow(screenRange.end.row + 1) - top
      width = @presenter.getScrollWidth()
    else
      {top, left} = @pixelPositionForScreenPosition(screenRange.start, false)
      height = @topPixelPositionForRow(screenRange.end.row + 1) - top
      width = @pixelPositionForScreenPosition(screenRange.end, false).left - left

    {top, left, width, height}
