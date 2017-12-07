const {Document} = require('tree-sitter')
const {Point, Range, Emitter} = require('atom')
const ScopeDescriptor = require('./scope-descriptor')
const TokenizedLine = require('./tokenized-line')

let nextId = 0

module.exports =
class TreeSitterLanguageMode {
  constructor ({buffer, grammar, config}) {
    this.id = nextId++
    this.buffer = buffer
    this.grammar = grammar
    this.config = config
    this.document = new Document()
    this.document.setInput(new TreeSitterTextBufferInput(buffer))
    this.document.setLanguage(grammar.languageModule)
    this.document.parse()
    this.rootScopeDescriptor = new ScopeDescriptor({scopes: [this.grammar.id]})
    this.emitter = new Emitter()
    this.isFoldableCache = []
  }

  getLanguageId () {
    return this.grammar.id
  }

  bufferDidChange ({oldRange, newRange, oldText, newText}) {
    const startRow = oldRange.start.row
    const oldEndRow = oldRange.end.row
    const newEndRow = newRange.end.row
    this.isFoldableCache.splice(startRow, oldEndRow - startRow, ...new Array(newEndRow - startRow))
    this.document.edit({
      startIndex: this.buffer.characterIndexForPosition(oldRange.start),
      lengthRemoved: oldText.length,
      lengthAdded: newText.length,
      startPosition: oldRange.start,
      extentRemoved: oldRange.getExtent(),
      extentAdded: newRange.getExtent()
    })
  }

  /*
   * Section - Highlighting
   */

  buildHighlightIterator () {
    const invalidatedRanges = this.document.parse()
    for (let i = 0, n = invalidatedRanges.length; i < n; i++) {
      const range = invalidatedRanges[i]
      const startRow = range.start.row
      const endRow = range.end.row
      for (let row = startRow; row < endRow; row++) {
        this.isFoldableCache[row] = undefined
      }
      this.emitter.emit('did-change-highlighting', range)
    }
    return new TreeSitterHighlightIterator(this)
  }

  onDidChangeHighlighting (callback) {
    return this.emitter.on('did-change-hightlighting', callback)
  }

  classNameForScopeId (scopeId) {
    return this.grammar.classNameForScopeId(scopeId)
  }

  /*
   * Section - Commenting
   */

  commentStringsForPosition () {
    return this.grammar.commentStrings
  }

  isRowCommented () {
    return false
  }

  /*
   * Section - Indentation
   */

  suggestedIndentForLineAtBufferRow (row, line, tabLength) {
    return this.suggestedIndentForBufferRow(row, tabLength)
  }

  suggestedIndentForBufferRow (row, tabLength, options) {
    let precedingRow
    if (!options || options.skipBlankLines !== false) {
      precedingRow = this.buffer.previousNonBlankRow(row)
      if (precedingRow == null) return 0
    } else {
      precedingRow = row - 1
      if (precedingRow < 0) return 0
    }

    return this.indentLevelForLine(this.buffer.lineForRow(precedingRow), tabLength)
  }

  suggestedIndentForEditedBufferRow (row) {
    return null
  }

  indentLevelForLine (line, tabLength = tabLength) {
    let indentLength = 0
    for (let i = 0, {length} = line; i < length; i++) {
      const char = line[i]
      if (char === '\t') {
        indentLength += tabLength - (indentLength % tabLength)
      } else if (char === ' ') {
        indentLength++
      } else {
        break
      }
    }
    return indentLength / tabLength
  }

  /*
   * Section - Folding
   */

  isFoldableAtRow (row) {
    if (this.isFoldableCache[row] != null) return this.isFoldableCache[row]
    const result = this.getFoldableRangeContainingPoint(Point(row, Infinity), 0, true) != null
    this.isFoldableCache[row] = result
    return result
  }

  getFoldableRanges () {
    return this.getFoldableRangesAtIndentLevel(null)
  }

  getFoldableRangesAtIndentLevel (goalLevel) {
    let result = []
    let stack = [{node: this.document.rootNode, level: 0}]
    while (stack.length > 0) {
      const {node, level} = stack.pop()

      const range = this.getFoldableRangeForNode(node)
      if (range) {
        if (goalLevel == null || level === goalLevel) {
          let updatedExistingRange = false
          for (let i = 0, {length} = result; i < length; i++) {
            if (result[i].start.row === range.start.row &&
                result[i].end.row === range.end.row) {
              result[i] = range
              updatedExistingRange = true
            }
          }
          if (!updatedExistingRange) result.push(range)
        }
      }

      const parentStartRow = node.startPosition.row
      const parentEndRow = node.endPosition.row
      for (let children = node.namedChildren, i = 0, {length} = children; i < length; i++) {
        const child = children[i]
        const {startPosition: childStart, endPosition: childEnd} = child
        if (childEnd.row > childStart.row) {
          if (childStart.row === parentStartRow && childEnd.row === parentEndRow) {
            stack.push({node: child, level: level})
          } else {
            const childLevel = range.containsPoint(childStart) && range.containsPoint(childEnd)
              ? level + 1
              : level
            if (childLevel <= goalLevel || goalLevel == null) {
              stack.push({node: child, level: childLevel})
            }
          }
        }
      }
    }

    return result.sort((a, b) => a.start.row - b.start.row)
  }

  getFoldableRangeContainingPoint (point, tabLength, existenceOnly = false) {
    let node = this.document.rootNode.descendantForPosition(this.buffer.clipPosition(point))
    while (node) {
      if (existenceOnly && node.startPosition.row < point.row) break
      if (node.endPosition.row > point.row) {
        const range = this.getFoldableRangeForNode(node, existenceOnly)
        if (range) return range
      }
      node = node.parent
    }
  }

  getFoldableRangeForNode (node, existenceOnly) {
    const {children, type: nodeType} = node
    const childCount = children.length
    let childTypes

    for (var i = 0, {length} = this.grammar.folds; i < length; i++) {
      const foldEntry = this.grammar.folds[i]

      if (foldEntry.type) {
        if (typeof foldEntry.type === 'string') {
          if (foldEntry.type !== nodeType) continue
        } else {
          if (!foldEntry.type.includes(nodeType)) continue
        }
      }

      let foldStart
      const startEntry = foldEntry.start
      if (startEntry) {
        if (startEntry.index != null) {
          const child = children[startEntry.index]
          if (!child || (startEntry.type && startEntry.type !== child.type)) continue
          foldStart = child.endPosition
        } else {
          if (!childTypes) childTypes = children.map(child => child.type)
          const index = childTypes.indexOf(startEntry.type)
          if (index === -1) continue
          foldStart = children[index].endPosition
        }
      }

      let foldEnd
      const endEntry = foldEntry.end
      if (endEntry) {
        let foldEndNode
        if (endEntry.index != null) {
          const index = endEntry.index < 0 ? childCount + endEntry.index : endEntry.index
          foldEndNode = children[index]
          if (!foldEndNode || (endEntry.type && endEntry.type !== foldEndNode.type)) continue
        } else {
          if (!childTypes) childTypes = children.map(foldEndNode => foldEndNode.type)
          const index = childTypes.lastIndexOf(endEntry.type)
          if (index === -1) continue
          foldEndNode = children[index]
        }

        if (foldEndNode.endIndex - foldEndNode.startIndex > 1 && foldEndNode.startPosition.row > foldStart.row) {
          foldEnd = new Point(foldEndNode.startPosition.row - 1, Infinity)
        } else {
          foldEnd = foldEndNode.startPosition
        }
      }

      if (existenceOnly) return true

      if (!foldStart) {
        foldStart = new Point(node.startPosition.row, Infinity)
      }

      if (!foldEnd) {
        const {endPosition} = node
        if (endPosition.column === 0) {
          foldEnd = Point(endPosition.row - 1, Infinity)
        } else if (childCount > 0) {
          foldEnd = endPosition
        } else {
          foldEnd = Point(endPosition.row, 0)
        }
      }

      return new Range(foldStart, foldEnd)
    }
  }

  /*
   * Syntax Tree APIs
   */

  getRangeForSyntaxNodeContainingRange (range) {
    const startIndex = this.buffer.characterIndexForPosition(range.start)
    const endIndex = this.buffer.characterIndexForPosition(range.end)
    let node = this.document.rootNode.descendantForIndex(startIndex, endIndex - 1)
    while (node && node.startIndex === startIndex && node.endIndex === endIndex) {
      node = node.parent
    }
    if (node) return new Range(node.startPosition, node.endPosition)
  }

  /*
   * Section - Backward compatibility shims
   */

  tokenizedLineForRow (row) {
    return new TokenizedLine({
      openScopes: [],
      text: this.buffer.lineForRow(row),
      tags: [],
      ruleStack: [],
      lineEnding: this.buffer.lineEndingForRow(row),
      tokenIterator: null,
      grammar: this.grammar
    })
  }

  scopeDescriptorForPosition (point) {
    return this.rootScopeDescriptor
  }

  hasTokenForSelector (scopeSelector) {
    return false
  }

  getGrammar () {
    return this.grammar
  }
}

class TreeSitterHighlightIterator {
  constructor (layer, document) {
    this.layer = layer

    // Conceptually, the iterator represents a single position in the text. It stores this
    // position both as a character index and as a `Point`. This position corresponds to a
    // leaf node of the syntax tree, which either contains or follows the iterator's
    // textual position. The `currentNode` property represents that leaf node, and
    // `currentChildIndex` represents the child index of that leaf node within its parent.
    this.currentIndex = null
    this.currentPosition = null
    this.currentNode = null
    this.currentChildIndex = null

    // In order to determine which selectors match its current node, the iterator maintains
    // a list of the current node's ancestors. Because the selectors can use the `:nth-child`
    // pseudo-class, each node's child index is also stored.
    this.containingNodeTypes = []
    this.containingNodeChildIndices = []

    // At any given position, the iterator exposes the list of class names that should be
    // *ended* at its current position and the list of class names that should be *started*
    // at its current position.
    this.closeTags = []
    this.openTags = []
  }

  seek (targetPosition) {
    const containingTags = []

    this.closeTags.length = 0
    this.openTags.length = 0
    this.containingNodeTypes.length = 0
    this.containingNodeChildIndices.length = 0
    this.currentPosition = targetPosition
    this.currentIndex = this.layer.buffer.characterIndexForPosition(targetPosition)

    var node = this.layer.document.rootNode
    var childIndex = -1
    var done = false
    var nodeContainsTarget = true
    do {
      this.currentNode = node
      this.currentChildIndex = childIndex
      this.containingNodeTypes.push(node.type)
      this.containingNodeChildIndices.push(childIndex)
      if (!nodeContainsTarget) break

      const scopeName = this.currentScopeName()
      if (scopeName) {
        const id = this.layer.grammar.idForScope(scopeName)
        if (this.currentIndex === node.startIndex) {
          this.openTags.push(id)
        } else {
          containingTags.push(id)
        }
      }

      done = true
      for (var i = 0, {children} = node, childCount = children.length; i < childCount; i++) {
        const child = children[i]
        if (child.endIndex > this.currentIndex) {
          node = child
          childIndex = i
          done = false
          if (child.startIndex > this.currentIndex) nodeContainsTarget = false
          break
        }
      }
    } while (!done)

    return containingTags
  }

  moveToSuccessor () {
    this.closeTags.length = 0
    this.openTags.length = 0

    if (!this.currentNode) {
      this.currentPosition = {row: Infinity, column: Infinity}
      return false
    }

    do {
      if (this.currentIndex < this.currentNode.startIndex) {
        this.currentIndex = this.currentNode.startIndex
        this.currentPosition = this.currentNode.startPosition
        this.pushOpenTag()
        this.descendLeft()
      } else if (this.currentIndex < this.currentNode.endIndex) {
        while (true) {
          this.currentIndex = this.currentNode.endIndex
          this.currentPosition = this.currentNode.endPosition
          this.pushCloseTag()

          const {nextSibling} = this.currentNode
          if (nextSibling) {
            this.currentNode = nextSibling
            this.currentChildIndex++
            if (this.currentIndex === nextSibling.startIndex) {
              this.pushOpenTag()
              this.descendLeft()
            }
            break
          } else {
            this.currentNode = this.currentNode.parent
            this.currentChildIndex = last(this.containingNodeChildIndices)
            if (!this.currentNode) break
          }
        }
      } else {
        this.currentNode = this.currentNode.nextSibling
        if (this.currentNode) {
          this.currentChildIndex++
          this.currentPosition = this.currentNode.startPosition
          this.currentIndex = this.currentNode.startIndex
          this.pushOpenTag()
          this.descendLeft()
        }
      }
    } while (this.closeTags.length === 0 && this.openTags.length === 0 && this.currentNode)

    return true
  }

  getPosition () {
    return this.currentPosition
  }

  getCloseScopeIds () {
    return this.closeTags.slice()
  }

  getOpenScopeIds () {
    return this.openTags.slice()
  }

  // Private methods

  descendLeft () {
    let child
    while ((child = this.currentNode.firstChild) && this.currentIndex === child.startIndex) {
      this.currentNode = child
      this.currentChildIndex = 0
      this.pushOpenTag()
    }
  }

  currentScopeName () {
    return this.layer.grammar.scopeMap.get(
      this.containingNodeTypes,
      this.containingNodeChildIndices,
      this.currentNode.isNamed
    )
  }

  pushCloseTag () {
    const scopeName = this.currentScopeName()
    if (scopeName) this.closeTags.push(this.layer.grammar.idForScope(scopeName))
    this.containingNodeTypes.pop()
    this.containingNodeChildIndices.pop()
  }

  pushOpenTag () {
    this.containingNodeTypes.push(this.currentNode.type)
    this.containingNodeChildIndices.push(this.currentChildIndex)
    const scopeName = this.currentScopeName()
    if (scopeName) this.openTags.push(this.layer.grammar.idForScope(scopeName))
  }
}

class TreeSitterTextBufferInput {
  constructor (buffer) {
    this.buffer = buffer
    this.seek(0)
  }

  seek (characterIndex) {
    this.position = this.buffer.positionForCharacterIndex(characterIndex)
  }

  read () {
    const endPosition = this.buffer.clipPosition(this.position.traverse({row: 1000, column: 0}))
    const text = this.buffer.getTextInRange([this.position, endPosition])
    this.position = endPosition
    return text
  }
}

function last (array) {
  return array[array.length - 1]
}
