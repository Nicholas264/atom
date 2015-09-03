PaneContainer = require '../src/pane-container'
PaneAxisElement = require '../src/pane-axis-element'
PaneAxis = require '../src/pane-axis'

describe "PaneContainerElement", ->
  describe "when panes are added or removed", ->
    it "inserts or removes resize elements", ->
      childTagNames = ->
        child.nodeName.toLowerCase() for child in paneAxisElement.children

      paneAxis = new PaneAxis
      paneAxisElement = new PaneAxisElement().initialize(paneAxis)

      expect(childTagNames()).toEqual []

      paneAxis.addChild(new PaneAxis)
      expect(childTagNames()).toEqual [
        'atom-pane-axis'
      ]

      paneAxis.addChild(new PaneAxis)
      expect(childTagNames()).toEqual [
        'atom-pane-axis'
        'atom-pane-resize-handle'
        'atom-pane-axis'
      ]

      paneAxis.addChild(new PaneAxis)
      expect(childTagNames()).toEqual [
        'atom-pane-axis'
        'atom-pane-resize-handle'
        'atom-pane-axis'
        'atom-pane-resize-handle'
        'atom-pane-axis'
      ]

      paneAxis.removeChild(paneAxis.getChildren()[2])
      expect(childTagNames()).toEqual [
        'atom-pane-axis'
        'atom-pane-resize-handle'
        'atom-pane-axis'
      ]

    it "transfers focus to the next pane if a focused pane is removed", ->
      container = new PaneContainer
      containerElement = atom.views.getView(container)
      leftPane = container.getActivePane()
      leftPaneElement = atom.views.getView(leftPane)
      rightPane = leftPane.splitRight()
      rightPaneElement = atom.views.getView(rightPane)

      jasmine.attachToDOM(containerElement)
      rightPaneElement.focus()
      expect(document.activeElement).toBe rightPaneElement

      rightPane.destroy()
      expect(document.activeElement).toBe leftPaneElement

  describe "when a pane is split", ->
    it "builds appropriately-oriented atom-pane-axis elements", ->
      container = new PaneContainer
      containerElement = atom.views.getView(container)

      pane1 = container.getRoot()
      pane2 = pane1.splitRight()
      pane3 = pane2.splitDown()

      horizontalPanes = containerElement.querySelectorAll('atom-pane-container > atom-pane-axis.horizontal > atom-pane')
      expect(horizontalPanes.length).toBe 1
      expect(horizontalPanes[0]).toBe atom.views.getView(pane1)

      verticalPanes = containerElement.querySelectorAll('atom-pane-container > atom-pane-axis.horizontal > atom-pane-axis.vertical > atom-pane')
      expect(verticalPanes.length).toBe 2
      expect(verticalPanes[0]).toBe atom.views.getView(pane2)
      expect(verticalPanes[1]).toBe atom.views.getView(pane3)

      pane1.destroy()
      verticalPanes = containerElement.querySelectorAll('atom-pane-container > atom-pane-axis.vertical > atom-pane')
      expect(verticalPanes.length).toBe 2
      expect(verticalPanes[0]).toBe atom.views.getView(pane2)
      expect(verticalPanes[1]).toBe atom.views.getView(pane3)

  describe "when the resize element is dragged ", ->
    [container, containerElement] = []

    beforeEach ->
      container = new PaneContainer
      containerElement = atom.views.getView(container)
      document.querySelector('#jasmine-content').appendChild(containerElement)

    dragElementToPosition = (element, clientX) ->
      element.dispatchEvent(new MouseEvent('mousedown',
        view: window
        bubbles: true
        button: 0
      ))

      element.dispatchEvent(new MouseEvent 'mousemove',
        view: window
        bubbles: true
        clientX: clientX
      )

      element.dispatchEvent(new MouseEvent 'mouseup',
        iew: window
        bubbles: true
        button: 0
      )

    getElementWidth = (element) ->
      element.getBoundingClientRect().width

    expectPaneScale = (pairs...) ->
      for [pane, expectedFlexScale] in pairs
        expect(pane.getFlexScale()).toBeCloseTo(expectedFlexScale, 0.1)

    getResizeElement = (i) ->
      containerElement.querySelectorAll('atom-pane-resize-handle')[i]

    getPaneElement = (i) ->
      containerElement.querySelectorAll('atom-pane')[i]

    it "adds and removes panes in the direction that the pane is being dragged", ->
      leftPane = container.getActivePane()
      expectPaneScale [leftPane, 1]

      middlePane = leftPane.splitRight()
      expectPaneScale [leftPane, 1], [middlePane, 1]

      dragElementToPosition(
        getResizeElement(0),
        getElementWidth(getPaneElement(0)) / 2
      )
      expectPaneScale [leftPane, 0.5], [middlePane, 1.5]

      rightPane = middlePane.splitRight()
      expectPaneScale [leftPane, 0.5], [middlePane, 1.5], [rightPane, 1]

      dragElementToPosition(
        getResizeElement(1),
        getElementWidth(getPaneElement(0)) + getElementWidth(getPaneElement(1)) / 2
      )
      expectPaneScale [leftPane, 0.5], [middlePane, 0.75], [rightPane, 1.75]

      middlePane.close()
      expectPaneScale [leftPane, 0.44], [rightPane, 1.55]

      leftPane.close()
      expectPaneScale [rightPane, 1]

    it "splits or closes panes in orthogonal direction that the pane is being dragged", ->
      leftPane = container.getActivePane()
      expectPaneScale [leftPane, 1]

      rightPane = leftPane.splitRight()
      expectPaneScale [leftPane, 1], [rightPane, 1]

      dragElementToPosition(
        getResizeElement(0),
        getElementWidth(getPaneElement(0)) / 2
      )
      expectPaneScale [leftPane, 0.5], [rightPane, 1.5]

      # dynamically split pane, pane's flexScale will become to 1
      lowerPane = leftPane.splitDown()
      expectPaneScale [lowerPane, 1], [leftPane, 1], [leftPane.getParent(), 0.5]

      # dynamically close pane, the pane's flexscale will recorver to origin value
      lowerPane.close()
      expectPaneScale [leftPane, 0.5], [rightPane, 1.5]

    it "unsubscribes from mouse events when the pane is detached", ->
      container.getActivePane().splitRight()
      element = getResizeElement(0)
      spyOn(document, 'addEventListener').andCallThrough()
      spyOn(document, 'removeEventListener').andCallThrough()
      spyOn(element, 'resizeStopped').andCallThrough()

      element.dispatchEvent(new MouseEvent('mousedown',
        view: window
        bubbles: true
        button: 0
      ))

      waitsFor ->
        document.addEventListener.callCount is 2

      runs ->
        expect(element.resizeStopped.callCount).toBe 0
        container.destroy()
        expect(element.resizeStopped.callCount).toBe 1
        expect(document.removeEventListener.callCount).toBe 2

    it "does not throw an error when resized to fit content in a detached state", ->
      container.getActivePane().splitRight()
      element = getResizeElement(0)
      element.remove()
      expect(-> element.resizeToFitContent()).not.toThrow()

  describe "pane resizing", ->
    [leftPane, rightPane] = []

    beforeEach ->
      container = new PaneContainer
      leftPane = container.getActivePane()
      rightPane = leftPane.splitRight()

    describe "when pane:increase-size is triggered", ->
      it "increases the size of the pane", ->
        expect(leftPane.getFlexScale()).toBe 1
        expect(rightPane.getFlexScale()).toBe 1

        atom.commands.dispatch(atom.views.getView(leftPane), 'pane:increase-size')
        expect(leftPane.getFlexScale()).toBe 1.1
        expect(rightPane.getFlexScale()).toBe 1

        atom.commands.dispatch(atom.views.getView(rightPane), 'pane:increase-size')
        expect(leftPane.getFlexScale()).toBe 1.1
        expect(rightPane.getFlexScale()).toBe 1.1

    describe "when pane:decrease-size is triggered", ->
      it "decreases the size of the pane", ->
        expect(leftPane.getFlexScale()).toBe 1
        expect(rightPane.getFlexScale()).toBe 1

        atom.commands.dispatch(atom.views.getView(leftPane), 'pane:decrease-size')
        expect(leftPane.getFlexScale()).toBe 1/1.1
        expect(rightPane.getFlexScale()).toBe 1

        atom.commands.dispatch(atom.views.getView(rightPane), 'pane:decrease-size')
        expect(leftPane.getFlexScale()).toBe 1/1.1
        expect(rightPane.getFlexScale()).toBe 1/1.1
