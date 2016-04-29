{Point} = require 'text-buffer'
{isPairedCharacter} = require './text-utils'

module.exports =
class LinesYardstick
  constructor: (@model, @lineNodesProvider, @lineTopIndex, grammarRegistry) ->
    @rangeForMeasurement = document.createRange()
    @invalidateCache()

  invalidateCache: ->
    @leftPixelPositionCache = {}

  measuredRowForPixelPosition: (pixelPosition) ->
    targetTop = pixelPosition.top
    row = Math.floor(targetTop / @model.getLineHeightInPixels())
    row if 0 <= row <= @model.getLastScreenRow()

  screenPositionForPixelPosition: (pixelPosition) ->
    targetTop = pixelPosition.top
    targetLeft = pixelPosition.left
    defaultCharWidth = @model.getDefaultCharWidth()
    row = @lineTopIndex.rowForPixelPosition(targetTop)
    targetLeft = 0 if targetTop < 0 or targetLeft < 0
    targetLeft = Infinity if row > @model.getLastScreenRow()
    row = Math.min(row, @model.getLastScreenRow())
    row = Math.max(0, row)

    lineNode = @lineNodesProvider.lineNodeForScreenRow(row)
    return Point(row, 0) unless lineNode

    textNodes = @lineNodesProvider.textNodesForScreenRow(row)
    lineOffset = lineNode.getBoundingClientRect().left
    targetLeft += lineOffset

    textNodeIndex = -1
    low = 0
    high = textNodes.length - 1
    while low <= high
      mid = low + (high - low >> 1)
      textNode = textNodes[mid]
      rangeRect = @clientRectForRange(textNode, 0, textNode.length)
      if targetLeft < rangeRect.left
        high = mid - 1
      else if targetLeft > rangeRect.right
        low = mid + 1
      else
        textNodeIndex = mid
        break

    if textNodeIndex is -1
      textNodesExtent = 0
      textNodesExtent += textContent.length for {textContent} in textNodes
      Point(row, textNodesExtent)
    else
      textNode = textNodes[textNodeIndex]
      characterIndex = -1
      low = 0
      high = textNode.textContent.length - 1
      while low <= high
        charIndex = low + (high - low >> 1)
        if isPairedCharacter(textNode.textContent, charIndex)
          nextCharIndex = charIndex + 2
        else
          nextCharIndex = charIndex + 1

        rangeRect = @clientRectForRange(textNode, charIndex, nextCharIndex)
        if targetLeft < rangeRect.left
          high = charIndex - 1
        else if targetLeft > rangeRect.right
          low = nextCharIndex
        else
          if targetLeft <= ((rangeRect.left + rangeRect.right) / 2)
            characterIndex = charIndex
          else
            characterIndex = nextCharIndex
          break

      textNodeStartColumn = 0
      textNodeStartColumn += textNodes[i].length for i in [0...textNodeIndex] by 1
      Point(row, textNodeStartColumn + characterIndex)

  pixelPositionForScreenPosition: (screenPosition) ->
    targetRow = screenPosition.row
    targetColumn = screenPosition.column

    top = @lineTopIndex.pixelPositionAfterBlocksForRow(targetRow)
    left = @leftPixelPositionForScreenPosition(targetRow, targetColumn)

    {top, left}

  leftPixelPositionForScreenPosition: (row, column) ->
    lineNode = @lineNodesProvider.lineNodeForScreenRow(row)
    lineId = @lineNodesProvider.lineIdForScreenRow(row)

    return 0 unless lineNode?

    if cachedPosition = @leftPixelPositionCache[lineId]?[column]
      return cachedPosition

    textNodes = @lineNodesProvider.textNodesForScreenRow(row)
    textNodeStartColumn = 0

    for textNode in textNodes
      textNodeEndColumn = textNodeStartColumn + textNode.textContent.length
      if textNodeEndColumn > column
        indexInTextNode = column - textNodeStartColumn
        break
      else
        textNodeStartColumn = textNodeEndColumn

    if textNode?
      indexInTextNode ?= textNode.textContent.length
      lineOffset = lineNode.getBoundingClientRect().left
      if indexInTextNode is 0
        leftPixelPosition = @clientRectForRange(textNode, 0, 1).left
      else
        leftPixelPosition = @clientRectForRange(textNode, 0, indexInTextNode).right
      leftPixelPosition -= lineOffset

      @leftPixelPositionCache[lineId] ?= {}
      @leftPixelPositionCache[lineId][column] = leftPixelPosition
      leftPixelPosition
    else
      0

  clientRectForRange: (textNode, startIndex, endIndex) ->
    @rangeForMeasurement.setStart(textNode, startIndex)
    @rangeForMeasurement.setEnd(textNode, endIndex)
    @rangeForMeasurement.getClientRects()[0] ? @rangeForMeasurement.getBoundingClientRect()
