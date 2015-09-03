PaneContainer = require '../src/pane-container'
PaneView = require '../src/pane-view'
fs = require 'fs-plus'
{Emitter, Disposable} = require 'event-kit'
{$, View} = require '../src/space-pen-extensions'
path = require 'path'
temp = require 'temp'

describe "PaneView", ->
  [container, containerModel, view1, view2, editor1, editor2, pane, paneModel, deserializerDisposable] = []

  class TestView extends View
    @deserialize: ({id, text}) -> new TestView({id, text})
    @content: ({id, text}) -> @div class: 'test-view', id: id, tabindex: -1, text
    initialize: ({@id, @text}) ->
      @emitter = new Emitter
    serialize: -> {deserializer: 'TestView', @id, @text}
    getURI: -> @id
    isEqual: (other) -> other? and @id is other.id and @text is other.text
    changeTitle: ->
      @emitter.emit 'did-change-title', 'title'
    onDidChangeTitle: (callback) ->
      @emitter.on 'did-change-title', callback
    onDidChangeModified: -> new Disposable(->)

  beforeEach ->
    jasmine.snapshotDeprecations()

    deserializerDisposable = atom.deserializers.add(TestView)
    container = atom.views.getView(new PaneContainer).__spacePenView
    containerModel = container.model
    view1 = new TestView(id: 'view-1', text: 'View 1')
    view2 = new TestView(id: 'view-2', text: 'View 2')
    waitsForPromise ->
      atom.workspace.open('sample.js').then (o) -> editor1 = o

    waitsForPromise ->
      atom.workspace.open('sample.txt').then (o) -> editor2 = o

    runs ->
      pane = container.getRoot()
      paneModel = pane.getModel()
      paneModel.addItems([view1, editor1, view2, editor2])

  afterEach ->
    deserializerDisposable.dispose()
    jasmine.restoreDeprecationsSnapshot()

  describe "drag and drop", ->
    buildDragEvent = (type, files) ->
      dataTransfer =
        files: files
        data: {}
        setData: (key, value) -> @data[key] = value
        getData: (key) -> @data[key]

      event = new CustomEvent("drop")
      event.dataTransfer = dataTransfer
      event

    describe "when a file is dragged to window", ->
      it "opens it", ->
        spyOn(atom, "open")
        event = buildDragEvent("drop", [ {path: "/fake1"}, {path: "/fake2"} ])
        pane[0].dispatchEvent(event)
        expect(atom.open.callCount).toBe 1
        expect(atom.open.argsForCall[0][0]).toEqual pathsToOpen: ['/fake1', '/fake2']

    describe "when a non-file is dragged to window", ->
      it "does nothing", ->
        spyOn(atom, "open")
        event = buildDragEvent("drop", [])
        pane[0].dispatchEvent(event)
        expect(atom.open).not.toHaveBeenCalled()
