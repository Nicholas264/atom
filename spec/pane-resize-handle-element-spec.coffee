PaneContainer = require '../src/pane-container'
PaneAxisElement = require '../src/pane-axis-element'
PaneAxis = require '../src/pane-axis'

describe "PaneResizeHandleElement", ->
  describe "when add or remove panes in PaneAxisElement", ->
    [paneAxisElement, paneAxis] = []

    beforeEach ->
      paneAxisElement = document.createElement('atom-pane-axis')
      paneAxis = new PaneAxis({})
      paneAxisElement.initialize(paneAxis)
      document.querySelector('#jasmine-content').appendChild(paneAxisElement)

    it "inserts or remove resize elements", ->
      expectPaneAxisElement = (index) ->
        child = paneAxisElement.children[index]
        expect(child.nodeName.toLowerCase()).toBe('atom-pane-axis')

      expectResizeElement = (index) ->
        child = paneAxisElement.children[index]
        expect(paneAxisElement.isPaneResizeHandleElement(child)).toBe(true)

      models = (new PaneAxis({}) for i in [0..2])
      paneAxis.addChild(models[0])
      paneAxis.addChild(models[1])
      expectResizeElement(1)

      paneAxis.addChild(models[2])
      expectPaneAxisElement(i) for i in [0, 2, 4]
      expectResizeElement(i) for i in [1, 3]

      # test removeChild
      paneAxis.removeChild(models[2])
      expectResizeElement(i) for i in [1, 3]

  describe "when user drag the resize element", ->
    [container, containerElement] = []
    [resizeElementMove, getElementWidth, expectFlexScale] = []

    beforeEach ->
      container = new PaneContainer
      containerElement = atom.views.getView(container);
      document.querySelector('#jasmine-content').appendChild(containerElement)

      resizeElementMove = (resizeElement, clientX, clientY) ->
        mouseDownEvent = new MouseEvent 'mousedown',
          { view: window, bubbles: true, button: 0 }
        resizeElement.dispatchEvent(mouseDownEvent)

        mouseMoveEvent = new MouseEvent 'mousemove',
          { view: window, bubbles: true, clientX: clientX, clientY: clientY}
        resizeElement.dispatchEvent(mouseMoveEvent)

        mouseUpEvent = new MouseEvent 'mouseup',
          {view: window, bubbles: true, button: 0}
        resizeElement.dispatchEvent(mouseUpEvent)

      getElementWidth = (element) ->
        element.getBoundingClientRect().width

      # assert the pane's flex scale. arguments is list of pane-scale pair
      expectFlexScale = ->
        args = Array::slice.apply(arguments, 0)
        for paneScale in args
          expect(paneScale[0].getFlexScale()).toBeCloseTo(paneScale[1], 0.1)

    it "add and remove panes in the same direction", ->
      leftPane = container.getActivePane()
      middlePane = leftPane.splitRight()

      resizeElements = containerElement.querySelectorAll('atom-pane-resize-handle')
      paneElements = containerElement.querySelectorAll('atom-pane')
      expect(resizeElements.length).toBe(2)

      resizeElementMove(resizeElements[0], getElementWidth(paneElements[0]) / 2)
      expectPaneScale [leftPane, 0.5], [middlePane, 1.5]

      rightPane = middlePane.splitRight()
      clientX = getElementWidth(paneElements[0]) + getElementWidth(paneElements[1]) / 2
      resizeElementMove(resizeElements[1], clientX)
      expectPaneScale [leftPane, 0.5], [middlePane, 0.75], [rightPane, 1.75]

      middlePane.close()
      expectPaneScale [leftPane, 0.44], [rightPane, 1.55]

      leftPane.close()
      expectPaneScale [rightPane, 1]

    it "split or close panes in orthogonal direction", ->
      leftPane = container.getActivePane()
      rightPane = leftPane.splitRight()

      resizeElement = containerElement.querySelector('atom-pane-resize-handle')
      resizeElementMove(resizeElement, getElementWidth(resizeElement.previousSibling) / 2)

      # dynamically split pane, pane's flexScale will become to 1
      lowerPane = leftPane.splitDown()
      expectPaneScale [lowerPane, 1], [leftPane, 1], [leftPane.getParent(), 0.5]

      # dynamically close pane, the pane's flexscale will recorver to origin value
      lowerPane.close()
      expectPaneScale [leftPane, 0.5], [rightPane, 1.5]


