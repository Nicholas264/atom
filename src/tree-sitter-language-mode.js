const Parser = require('tree-sitter')
const {Point, Range} = require('text-buffer')
const {Emitter, Disposable} = require('event-kit')
const ScopeDescriptor = require('./scope-descriptor')
const TokenizedLine = require('./tokenized-line')
const TextMateLanguageMode = require('./text-mate-language-mode')

let nextId = 0

module.exports =
class TreeSitterLanguageMode {
  constructor ({buffer, grammar, config}) {
    this.id = nextId++
    this.buffer = buffer
    this.grammar = grammar
    this.config = config
    this.parser = new Parser()
    this.parser.setLanguage(grammar.languageModule)
    this.tree = this.parser.parseTextBufferSync(this.buffer.buffer)
    this.rootScopeDescriptor = new ScopeDescriptor({scopes: [this.grammar.id]})
    this.emitter = new Emitter()
    this.isFoldableCache = []
    this.hasQueuedParse = false
    this.buffer.onDidChangeText(async () => {
      if (!this.reparsePromise) {
        this.reparsePromise = this.reparse().then(() => {
          this.reparsePromise = null
        })
      }
    })

    // TODO: Remove this once TreeSitterLanguageMode implements its own auto-indentation system. This
    // is temporarily needed in order to delegate to the TextMateLanguageMode's auto-indent system.
    this.regexesByPattern = {}
  }

  getLanguageId () {
    return this.grammar.id
  }

  bufferDidChange ({oldRange, newRange, oldText, newText}) {
    const startRow = oldRange.start.row
    const oldEndRow = oldRange.end.row
    const newEndRow = newRange.end.row
    this.isFoldableCache.splice(startRow, oldEndRow - startRow, ...new Array(newEndRow - startRow))
    this.tree.edit({
      startIndex: this.buffer.characterIndexForPosition(oldRange.start),
      lengthRemoved: oldText.length,
      lengthAdded: newText.length,
      startPosition: oldRange.start,
      extentRemoved: oldRange.getExtent(),
      extentAdded: newRange.getExtent()
    })
  }

  /*
  Section - Highlighting
  */

  async reparse () {
    const tree = await this.parser.parseTextBuffer(this.buffer.buffer, this.tree)
    const invalidatedRanges = tree.getChangedRanges(this.tree)
    this.tree = tree
    for (let i = 0, n = invalidatedRanges.length; i < n; i++) {
      const range = invalidatedRanges[i]
      const startRow = range.start.row
      const endRow = range.end.row
      for (let row = startRow; row < endRow; row++) {
        this.isFoldableCache[row] = undefined
      }
      this.emitter.emit('did-change-highlighting', range)
    }
  }

  buildHighlightIterator () {
    return new TreeSitterHighlightIterator(this)
  }

  onDidChangeHighlighting (callback) {
    return this.emitter.on('did-change-highlighting', callback)
  }

  classNameForScopeId (scopeId) {
    return this.grammar.classNameForScopeId(scopeId)
  }

  /*
  Section - Commenting
  */

  commentStringsForPosition () {
    return this.grammar.commentStrings
  }

  isRowCommented () {
    return false
  }

  /*
  Section - Indentation
  */

  suggestedIndentForLineAtBufferRow (row, line, tabLength) {
    return this._suggestedIndentForLineWithScopeAtBufferRow(
      row,
      line,
      this.rootScopeDescriptor,
      tabLength
    )
  }

  suggestedIndentForBufferRow (row, tabLength, options) {
    return this._suggestedIndentForLineWithScopeAtBufferRow(
      row,
      this.buffer.lineForRow(row),
      this.rootScopeDescriptor,
      tabLength,
      options
    )
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
  Section - Folding
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
    let stack = [{node: this.tree.rootNode, level: 0}]
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
              break
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
            const childLevel = range && range.containsPoint(childStart) && range.containsPoint(childEnd)
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
    let node = this.tree.rootNode.descendantForPosition(this.buffer.clipPosition(point))
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
          const index = typeof startEntry.type === 'string'
            ? childTypes.indexOf(startEntry.type)
            : childTypes.findIndex(type => startEntry.type.includes(type))
          if (index === -1) continue
          foldStart = children[index].endPosition
        }
      } else {
        foldStart = new Point(node.startPosition.row, Infinity)
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
          const index = typeof endEntry.type === 'string'
            ? childTypes.indexOf(endEntry.type)
            : childTypes.findIndex(type => endEntry.type.includes(type))
          if (index === -1) continue
          foldEndNode = children[index]
        }

        if (foldEndNode.endIndex - foldEndNode.startIndex > 1 && foldEndNode.startPosition.row > foldStart.row) {
          foldEnd = new Point(foldEndNode.startPosition.row - 1, Infinity)
        } else {
          foldEnd = foldEndNode.startPosition
        }
      } else {
        const {endPosition} = node
        if (endPosition.column === 0) {
          foldEnd = Point(endPosition.row - 1, Infinity)
        } else if (childCount > 0) {
          foldEnd = endPosition
        } else {
          foldEnd = Point(endPosition.row, 0)
        }
      }

      return existenceOnly ? true : new Range(foldStart, foldEnd)
    }
  }

  /*
  Syntax Tree APIs
  */

  getRangeForSyntaxNodeContainingRange (range) {
    const startIndex = this.buffer.characterIndexForPosition(range.start)
    const endIndex = this.buffer.characterIndexForPosition(range.end)
    let node = this.tree.rootNode.descendantForIndex(startIndex, endIndex - 1)
    while (node && node.startIndex === startIndex && node.endIndex === endIndex) {
      node = node.parent
    }
    if (node) return new Range(node.startPosition, node.endPosition)
  }

  bufferRangeForScopeAtPosition (position) {
    return this.getRangeForSyntaxNodeContainingRange(new Range(position, position))
  }

  /*
  Section - Backward compatibility shims
  */

  onDidTokenize (callback) { return new Disposable(() => {}) }

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
    point = Point.fromObject(point)
    const result = []
    let node = this.tree.rootNode.descendantForPosition(point)

    // Don't include anonymous token types like '(' because they prevent scope chains
    // from being parsed as CSS selectors by the `slick` parser. Other css selector
    // parsers like `postcss-selector-parser` do allow arbitrary quoted strings in
    // selectors.
    if (!node.isNamed) node = node.parent

    while (node) {
      result.push(node.type)
      node = node.parent
    }
    result.push(this.grammar.id)
    return new ScopeDescriptor({scopes: result.reverse()})
  }

  hasTokenForSelector (scopeSelector) {
    return false
  }

  getGrammar () {
    return this.grammar
  }
}

class TreeSitterHighlightIterator {
  constructor (layer) {
    this.layer = layer
    this.treeCursor = this.layer.tree.walk()

    // Conceptually, the iterator represents a single position in the text. It stores this
    // position both as a character index and as a `Point`. This position corresponds to a
    // leaf node of the syntax tree, which either contains or follows the iterator's
    // textual position. The `treeCursor` property points at that leaf node, and
    // `currentChildIndex` represents the child index of that leaf node within its parent.
    this.currentIndex = null
    this.currentPosition = null
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
    while (this.treeCursor.gotoParent()) {}

    const containingTags = []

    this.closeTags.length = 0
    this.openTags.length = 0
    this.containingNodeTypes.length = 0
    this.containingNodeChildIndices.length = 0
    this.currentPosition = targetPosition
    this.currentIndex = this.layer.buffer.characterIndexForPosition(targetPosition)

    var childIndex = -1
    var nodeContainsTarget = true
    for (;;) {
      this.currentChildIndex = childIndex
      if (!nodeContainsTarget) break
      this.containingNodeTypes.push(this.treeCursor.nodeType)
      this.containingNodeChildIndices.push(childIndex)

      const scopeName = this.currentScopeName()
      if (scopeName) {
        const id = this.layer.grammar.idForScope(scopeName)
        if (this.currentIndex === this.treeCursor.startIndex) {
          this.openTags.push(id)
        } else {
          containingTags.push(id)
        }
      }

      const nextChildIndex = this.treeCursor.gotoFirstChildForIndex(this.currentIndex)
      if (nextChildIndex == null) break
      if (this.treeCursor.startIndex > this.currentIndex) nodeContainsTarget = false
      childIndex = nextChildIndex
    }

    return containingTags
  }

  moveToSuccessor () {
    this.closeTags.length = 0
    this.openTags.length = 0

    do {
      if (this.currentIndex < this.treeCursor.startIndex) {
        this.currentIndex = this.treeCursor.startIndex
        this.currentPosition = this.treeCursor.startPosition
        this.pushOpenTag()
        this.descendLeft()
      } else if (this.currentIndex < this.treeCursor.endIndex) {
        while (true) {
          this.currentIndex = this.treeCursor.endIndex
          this.currentPosition = this.treeCursor.endPosition
          this.pushCloseTag()

          if (this.treeCursor.gotoNextSibling()) {
            this.currentChildIndex++
            if (this.currentIndex === this.treeCursor.startIndex) {
              this.pushOpenTag()
              this.descendLeft()
            }
            break
          } else {
            this.currentChildIndex = last(this.containingNodeChildIndices)
            if (!this.treeCursor.gotoParent()) break
          }
        }
      } else if (!this.treeCursor.gotoNextSibling()) {
        this.currentPosition = {row: Infinity, column: Infinity}
        break
      }
    } while (this.closeTags.length === 0 && this.openTags.length === 0)

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
    while (this.treeCursor.gotoFirstChild()) {
      this.currentChildIndex = 0
      this.pushOpenTag()
    }
  }

  currentScopeName () {
    return this.layer.grammar.scopeMap.get(
      this.containingNodeTypes,
      this.containingNodeChildIndices,
      this.treeCursor.nodeIsNamed
    )
  }

  pushCloseTag () {
    const scopeName = this.currentScopeName()
    if (scopeName) this.closeTags.push(this.layer.grammar.idForScope(scopeName))
    this.containingNodeTypes.pop()
    this.containingNodeChildIndices.pop()
  }

  pushOpenTag () {
    this.containingNodeTypes.push(this.treeCursor.nodeType)
    this.containingNodeChildIndices.push(this.currentChildIndex)
    const scopeName = this.currentScopeName()
    if (scopeName) this.openTags.push(this.layer.grammar.idForScope(scopeName))
  }
}

function last (array) {
  return array[array.length - 1]
}

// TODO: Remove this once TreeSitterLanguageMode implements its own auto-indent system.
[
  '_suggestedIndentForLineWithScopeAtBufferRow',
  'suggestedIndentForEditedBufferRow',
  'increaseIndentRegexForScopeDescriptor',
  'decreaseIndentRegexForScopeDescriptor',
  'decreaseNextIndentRegexForScopeDescriptor',
  'regexForPattern'
].forEach(methodName => {
  module.exports.prototype[methodName] = TextMateLanguageMode.prototype[methodName]
})
