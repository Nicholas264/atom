Gutter = require '../src/gutter'
GutterContainerComponent = require '../src/gutter-container-component'

describe "GutterContainerComponent", ->
  [gutterContainerComponent] = []
  mockGutterContainer = {}

  buildTestState = (gutters) ->
    styles =
      scrollHeight: 100
      scrollTop: 10
      backgroundColor: 'black'

    mockTestState = {gutters: []}
    for gutter in gutters
      if gutter.name is 'line-number'
        content = {maxLineNumberDigits: 10, lineNumbers: {}}
      else
        content = {}
      mockTestState.gutters.push({gutter, styles, content, visible: gutter.visible})

    mockTestState

  beforeEach ->
    mockEditor = {}
    mockMouseDown = ->
    gutterContainerComponent = new GutterContainerComponent({editor: mockEditor, onMouseDown: mockMouseDown})

  it "creates a DOM node with no child gutter nodes when it is initialized", ->
    expect(gutterContainerComponent.getDomNode() instanceof HTMLElement).toBe true
    expect(gutterContainerComponent.getDomNode().children.length).toBe 0

  describe "when updated with state that contains a new line-number gutter", ->
    it "adds a LineNumberGutterComponent to its children", ->
      lineNumberGutter = new Gutter(mockGutterContainer, {name: 'line-number'})
      testState = buildTestState([lineNumberGutter])

      expect(gutterContainerComponent.getDomNode().children.length).toBe 0
      gutterContainerComponent.updateSync(testState)
      expect(gutterContainerComponent.getDomNode().children.length).toBe 1
      expectedGutterNode = gutterContainerComponent.getDomNode().children.item(0)
      expect(expectedGutterNode.classList.contains('gutter')).toBe true
      expectedLineNumbersNode = expectedGutterNode.children.item(0)
      expect(expectedLineNumbersNode.classList.contains('line-numbers')).toBe true

      expect(gutterContainerComponent.getLineNumberGutterComponent().getDomNode()).toBe expectedGutterNode

  describe "when updated with state that contains a new custom gutter", ->
    it "adds a CustomGutterComponent to its children", ->
      customGutter = new Gutter(mockGutterContainer, {name: 'custom'})
      testState = buildTestState([customGutter])

      expect(gutterContainerComponent.getDomNode().children.length).toBe 0
      gutterContainerComponent.updateSync(testState)
      expect(gutterContainerComponent.getDomNode().children.length).toBe 1
      expectedGutterNode = gutterContainerComponent.getDomNode().children.item(0)
      expect(expectedGutterNode.classList.contains('gutter')).toBe true
      expectedCustomDecorationsNode = expectedGutterNode.children.item(0)
      expect(expectedCustomDecorationsNode.classList.contains('custom-decorations')).toBe true

  describe "when updated with state that contains a new gutter that is not visible", ->
    it "creates the gutter view but hides it, and unhides it when it is later updated to be visible", ->
      customGutter = new Gutter(mockGutterContainer, {name: 'custom', visible: false})
      testState = buildTestState([customGutter])

      gutterContainerComponent.updateSync(testState)
      expect(gutterContainerComponent.getDomNode().children.length).toBe 1
      expectedCustomGutterNode = gutterContainerComponent.getDomNode().children.item(0)
      expect(expectedCustomGutterNode.style.display).toBe 'none'

      customGutter.show()
      testState = buildTestState([customGutter])
      gutterContainerComponent.updateSync(testState)
      expect(gutterContainerComponent.getDomNode().children.length).toBe 1
      expectedCustomGutterNode = gutterContainerComponent.getDomNode().children.item(0)
      expect(expectedCustomGutterNode.style.display).toBe ''

  describe "when updated with a gutter that already exists", ->
    it "reuses the existing gutter view, instead of recreating it", ->
      customGutter = new Gutter(mockGutterContainer, {name: 'custom'})
      testState = buildTestState([customGutter])

      gutterContainerComponent.updateSync(testState)
      expect(gutterContainerComponent.getDomNode().children.length).toBe 1
      expectedCustomGutterNode = gutterContainerComponent.getDomNode().children.item(0)

      testState = buildTestState([customGutter])
      gutterContainerComponent.updateSync(testState)
      expect(gutterContainerComponent.getDomNode().children.length).toBe 1
      expect(gutterContainerComponent.getDomNode().children.item(0)).toBe expectedCustomGutterNode

  it "removes a gutter from the DOM if it does not appear in the latest state update", ->
    lineNumberGutter = new Gutter(mockGutterContainer, {name: 'line-number'})
    testState = buildTestState([lineNumberGutter])
    gutterContainerComponent.updateSync(testState)

    expect(gutterContainerComponent.getDomNode().children.length).toBe 1
    testState = buildTestState([])
    gutterContainerComponent.updateSync(testState)
    expect(gutterContainerComponent.getDomNode().children.length).toBe 0

  describe "when updated with multiple gutters", ->
    it "positions (and repositions) the gutters to match the order they appear in each state update", ->
      lineNumberGutter = new Gutter(mockGutterContainer, {name: 'line-number'})
      customGutter1 = new Gutter(mockGutterContainer, {name: 'custom', priority: -100})
      testState = buildTestState([customGutter1, lineNumberGutter])

      gutterContainerComponent.updateSync(testState)
      expect(gutterContainerComponent.getDomNode().children.length).toBe 2

      initialCustomGutterNode1 = gutterContainerComponent.getDomNode().children.item(0)
      initialLineNumbersNode = gutterContainerComponent.getDomNode().children.item(1)

      # Add a gutter.
      customGutter2 = new Gutter(mockGutterContainer, {name: 'custom2', priority: -10})
      testState = buildTestState([customGutter1, customGutter2, lineNumberGutter])
      gutterContainerComponent.updateSync(testState)

      expect(gutterContainerComponent.getDomNode().children.length).toBe 3

      unchangedCustomGutterNode1 = gutterContainerComponent.getDomNode().children.item(0)
      insertedCustomGutterNode2 = gutterContainerComponent.getDomNode().children.item(1)
      repositionedLineNumbersNode = gutterContainerComponent.getDomNode().children.item(2)

      expect(initialCustomGutterNode1).toBe(unchangedCustomGutterNode1)
      expect(initialLineNumbersNode).toBe(repositionedLineNumbersNode)
      expect(insertedCustomGutterNode2).toBeDefined()

      # Hide one gutter, reposition one gutter, remove one gutter; and add a new gutter.
      customGutter2.hide()
      customGutter3 = new Gutter(mockGutterContainer, {name: 'custom3', priority: 100})
      testState = buildTestState([customGutter2, customGutter1, customGutter3])
      gutterContainerComponent.updateSync(testState)
      expect(gutterContainerComponent.getDomNode().children.length).toBe 3

      repositionedCustomGutterNode2 = gutterContainerComponent.getDomNode().children.item(0)
      repositionedCustomGutterNode1 = gutterContainerComponent.getDomNode().children.item(1)
      insertedCustomGutterNode3 = gutterContainerComponent.getDomNode().children.item(2)

      expect(initialCustomGutterNode1).toBe(repositionedCustomGutterNode1)
      expect(repositionedCustomGutterNode2).toBe(insertedCustomGutterNode2)
      expect(repositionedCustomGutterNode2.style.display).toBe('none')
      expect(insertedCustomGutterNode3).toBeDefined()
