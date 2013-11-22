{View, $, $$} = require 'atom'

describe "SpacePen extensions", ->
  class TestView extends View
    @content: -> @div()

  [view, parent] = []

  beforeEach ->
    view = new TestView
    parent = $$ -> @div()
    parent.append(view)

  describe "View.observeConfig(keyPath, callback)", ->
    observeHandler = null

    beforeEach ->
      observeHandler = jasmine.createSpy("observeHandler")
      view.observeConfig "foo.bar", observeHandler
      expect(view.hasParent()).toBeTruthy()

    it "observes the keyPath and cancels the subscription when `.unobserveConfig()` is called", ->
      expect(observeHandler).toHaveBeenCalledWith(undefined)
      observeHandler.reset()

      atom.config.set("foo.bar", "hello")

      expect(observeHandler).toHaveBeenCalledWith("hello", previous: undefined)
      observeHandler.reset()

      view.unobserveConfig()

      atom.config.set("foo.bar", "goodbye")

      expect(observeHandler).not.toHaveBeenCalled()

    it "unobserves when the view is removed", ->
      observeHandler.reset()
      parent.remove()
      atom.config.set("foo.bar", "hello")
      expect(observeHandler).not.toHaveBeenCalled()

  describe "View.subscribe(eventEmitter, eventName, callback)", ->
    [emitter, eventHandler] = []

    beforeEach ->
      eventHandler = jasmine.createSpy 'eventHandler'
      emitter = $$ -> @div()
      view.subscribe emitter, 'foo', eventHandler

    it "subscribes to the given event emitter and unsubscribes when unsubscribe is called", ->
      emitter.trigger "foo"
      expect(eventHandler).toHaveBeenCalled()

  describe "tooltips", ->
    describe "replaceModifiers", ->
      replaceModifiers = $.fn.setTooltip.replaceModifiers

      it "replaces single keystroke", ->
        expect(replaceModifiers('cmd-O')).toEqual '⌘⇧O'
        expect(replaceModifiers('cmd-shift-up')).toEqual '⌘⇧↑'
        expect(replaceModifiers('cmd-option-down')).toEqual '⌘⌥↓'
        expect(replaceModifiers('cmd-option-left')).toEqual '⌘⌥←'
        expect(replaceModifiers('cmd-option-right')).toEqual '⌘⌥→'

      it "replaces multiple keystroke", ->
        expect(replaceModifiers('cmd-o ctrl-2')).toEqual '⌘O ⌃2'
