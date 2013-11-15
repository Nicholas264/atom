path = require 'path'

Keymap = require '../src/keymap'
{$, $$, RootView} = require 'atom'

describe "Keymap", ->
  fragment = null
  keymap = null
  resourcePath = atom.getLoadSettings().resourcePath

  beforeEach ->
    keymap = new Keymap({configDirPath: atom.getConfigDirPath(), resourcePath})
    fragment = $ """
      <div class="command-mode">
        <div class="child-node">
          <div class="grandchild-node"/>
        </div>
      </div>
    """

  describe ".handleKeyEvent(event)", ->
    deleteCharHandler = null
    insertCharHandler = null
    metaZHandler = null

    beforeEach ->
      keymap.bindKeys 'name', '.command-mode', 'x': 'deleteChar'
      keymap.bindKeys 'name', '.insert-mode', 'x': 'insertChar'
      keymap.bindKeys 'name', '.command-mode', 'meta-z': 'metaZPressed'

      deleteCharHandler = jasmine.createSpy('deleteCharHandler')
      insertCharHandler = jasmine.createSpy('insertCharHandler')
      metaZHandler = jasmine.createSpy('metaZHandler')
      fragment.on 'deleteChar', deleteCharHandler
      fragment.on 'insertChar', insertCharHandler
      fragment.on 'metaZPressed', metaZHandler

    describe "when no binding matches the event's keystroke", ->
      it "does not return false so the event continues to propagate", ->
        expect(keymap.handleKeyEvent(keydownEvent('0', target: fragment[0]))).not.toBe false

    describe "when a non-English keyboard language is used", ->
      it "uses the physical character pressed instead of the character it maps to in the current language", ->
        event = keydownEvent('U+03B6', metaKey: true, which: 122, target: fragment[0]) # This is the 'z' key using the Greek keyboard layout
        result = keymap.handleKeyEvent(event)

        expect(result).toBe(false)
        expect(metaZHandler).toHaveBeenCalled()

    describe "when at least one binding fully matches the event's keystroke", ->
      describe "when the event's target node matches a selector with a matching binding", ->
        it "triggers the command event associated with that binding on the target node and returns false", ->
          result = keymap.handleKeyEvent(keydownEvent('x', target: fragment[0]))
          expect(result).toBe(false)
          expect(deleteCharHandler).toHaveBeenCalled()
          expect(insertCharHandler).not.toHaveBeenCalled()

          deleteCharHandler.reset()
          fragment.removeClass('command-mode').addClass('insert-mode')

          event = keydownEvent('x', target: fragment[0])
          keymap.handleKeyEvent(event)
          expect(deleteCharHandler).not.toHaveBeenCalled()
          expect(insertCharHandler).toHaveBeenCalled()

      describe "when the event's target node *descends* from a selector with a matching binding", ->
        it "triggers the command event associated with that binding on the target node and returns false", ->
          target = fragment.find('.child-node')[0]
          result = keymap.handleKeyEvent(keydownEvent('x', target: target))
          expect(result).toBe(false)
          expect(deleteCharHandler).toHaveBeenCalled()
          expect(insertCharHandler).not.toHaveBeenCalled()

          deleteCharHandler.reset()
          fragment.removeClass('command-mode').addClass('insert-mode')

          keymap.handleKeyEvent(keydownEvent('x', target: target))
          expect(deleteCharHandler).not.toHaveBeenCalled()
          expect(insertCharHandler).toHaveBeenCalled()

      describe "when the event's target node descends from multiple nodes that match selectors with a binding", ->
        beforeEach ->
          keymap.bindKeys 'name', '.child-node', 'x': 'foo'

        it "only triggers bindings on selectors associated with the closest ancestor node", ->
          fooHandler = jasmine.createSpy 'fooHandler'
          fragment.on 'foo', fooHandler

          target = fragment.find('.grandchild-node')[0]
          keymap.handleKeyEvent(keydownEvent('x', target: target))
          expect(fooHandler).toHaveBeenCalled()
          expect(deleteCharHandler).not.toHaveBeenCalled()
          expect(insertCharHandler).not.toHaveBeenCalled()

        describe "when 'abortKeyBinding' is called on the triggered event", ->
          [fooHandler1, fooHandler2] = []

          beforeEach ->
            fooHandler1 = jasmine.createSpy('fooHandler1').andCallFake (e) ->
              expect(deleteCharHandler).not.toHaveBeenCalled()
              e.abortKeyBinding()
            fooHandler2 = jasmine.createSpy('fooHandler2')

            fragment.find('.child-node').on 'foo', fooHandler1
            fragment.on 'foo', fooHandler2

          it "aborts the current event and tries again with the next-most-specific key binding",  ->
            target = fragment.find('.grandchild-node')[0]
            keymap.handleKeyEvent(keydownEvent('x', target: target))
            expect(fooHandler1).toHaveBeenCalled()
            expect(fooHandler2).not.toHaveBeenCalled()
            expect(deleteCharHandler).toHaveBeenCalled()

          it "does not throw an exception if the event was not triggered by the keymap",  ->
            fragment.find('.grandchild-node').trigger 'foo'

      describe "when the event bubbles to a node that matches multiple selectors", ->
        describe "when the matching selectors differ in specificity", ->
          it "triggers the binding for the most specific selector", ->
            keymap.bindKeys 'name', 'div .child-node', 'x': 'foo'
            keymap.bindKeys 'name', '.command-mode .child-node !important', 'x': 'baz'
            keymap.bindKeys 'name', '.command-mode .child-node', 'x': 'quux'
            keymap.bindKeys 'name', '.child-node', 'x': 'bar'

            fooHandler = jasmine.createSpy 'fooHandler'
            barHandler = jasmine.createSpy 'barHandler'
            bazHandler = jasmine.createSpy 'bazHandler'
            fragment.on 'foo', fooHandler
            fragment.on 'bar', barHandler
            fragment.on 'baz', bazHandler

            target = fragment.find('.grandchild-node')[0]
            keymap.handleKeyEvent(keydownEvent('x', target: target))

            expect(fooHandler).not.toHaveBeenCalled()
            expect(barHandler).not.toHaveBeenCalled()
            expect(bazHandler).toHaveBeenCalled()

        describe "when the matching selectors have the same specificity", ->
          it "triggers the bindings for the most recently declared selector", ->
            keymap.bindKeys 'name', '.child-node', 'x': 'foo', 'y': 'baz'
            keymap.bindKeys 'name', '.child-node', 'x': 'bar'

            fooHandler = jasmine.createSpy 'fooHandler'
            barHandler = jasmine.createSpy 'barHandler'
            bazHandler = jasmine.createSpy 'bazHandler'
            fragment.on 'foo', fooHandler
            fragment.on 'bar', barHandler
            fragment.on 'baz', bazHandler

            target = fragment.find('.grandchild-node')[0]
            keymap.handleKeyEvent(keydownEvent('x', target: target))

            expect(barHandler).toHaveBeenCalled()
            expect(fooHandler).not.toHaveBeenCalled()

            keymap.handleKeyEvent(keydownEvent('y', target: target))
            expect(bazHandler).toHaveBeenCalled()

      describe "when the event's target is the document body", ->
        it "triggers the mapped event on the rootView", ->
          window.rootView = new RootView
          rootView.attachToDom()
          keymap.bindKeys 'name', 'body', 'x': 'foo'
          fooHandler = jasmine.createSpy("fooHandler")
          rootView.on 'foo', fooHandler

          result = keymap.handleKeyEvent(keydownEvent('x', target: document.body))
          expect(result).toBe(false)
          expect(fooHandler).toHaveBeenCalled()
          expect(deleteCharHandler).not.toHaveBeenCalled()
          expect(insertCharHandler).not.toHaveBeenCalled()

      describe "when the event matches a 'native!' binding", ->
        it "returns true, allowing the browser's native key handling to process the event", ->
          keymap.bindKeys 'name', '.grandchild-node', 'x': 'native!'
          nativeHandler = jasmine.createSpy("nativeHandler")
          fragment.on 'native!', nativeHandler
          expect(keymap.handleKeyEvent(keydownEvent('x', target: fragment.find('.grandchild-node')[0]))).toBe true
          expect(nativeHandler).not.toHaveBeenCalled()

    describe "when at least one binding partially matches the event's keystroke", ->
      [quitHandler, closeOtherWindowsHandler] = []

      beforeEach ->
        keymap.bindKeys 'name', "*",
          'ctrl-x ctrl-c': 'quit'
          'ctrl-x 1': 'close-other-windows'

        quitHandler = jasmine.createSpy('quitHandler')
        closeOtherWindowsHandler = jasmine.createSpy('closeOtherWindowsHandler')
        fragment.on 'quit', quitHandler
        fragment.on 'close-other-windows', closeOtherWindowsHandler

      it "only matches entire keystroke patterns", ->
        expect(keymap.handleKeyEvent(keydownEvent('c', target: fragment[0]))).not.toBe false

      describe "when the event's target node matches a selector with a partially matching multi-stroke binding", ->
        describe "when a second keystroke added to the first to match a multi-stroke binding completely", ->
          it "triggers the event associated with the matched multi-stroke binding", ->
            expect(keymap.handleKeyEvent(keydownEvent('x', target: fragment[0], ctrlKey: true))).toBeFalsy()
            expect(keymap.handleKeyEvent(keydownEvent('ctrl', target: fragment[0]))).toBeFalsy() # This simulates actual key event behavior
            expect(keymap.handleKeyEvent(keydownEvent('c', target: fragment[0], ctrlKey: true))).toBeFalsy()

            expect(quitHandler).toHaveBeenCalled()
            expect(closeOtherWindowsHandler).not.toHaveBeenCalled()
            quitHandler.reset()

            expect(keymap.handleKeyEvent(keydownEvent('x', target: fragment[0], ctrlKey: true))).toBeFalsy()
            expect(keymap.handleKeyEvent(keydownEvent('1', target: fragment[0]))).toBeFalsy()

            expect(quitHandler).not.toHaveBeenCalled()
            expect(closeOtherWindowsHandler).toHaveBeenCalled()

        describe "when a second keystroke added to the first doesn't match any bindings", ->
          it "clears the queued keystroke without triggering any events", ->
            expect(keymap.handleKeyEvent(keydownEvent('x', target: fragment[0], ctrlKey: true))).toBe false
            expect(keymap.handleKeyEvent(keydownEvent('c', target: fragment[0]))).toBe false
            expect(quitHandler).not.toHaveBeenCalled()
            expect(closeOtherWindowsHandler).not.toHaveBeenCalled()

            expect(keymap.handleKeyEvent(keydownEvent('c', target: fragment[0]))).not.toBe false

      describe "when the event's target node descends from multiple nodes that match selectors with a partial binding match", ->
        it "allows any of the bindings to be triggered upon a second keystroke, favoring the most specific selector", ->
          keymap.bindKeys 'name', ".grandchild-node", 'ctrl-x ctrl-c': 'more-specific-quit'
          grandchildNode = fragment.find('.grandchild-node')[0]
          moreSpecificQuitHandler = jasmine.createSpy('moreSpecificQuitHandler')
          fragment.on 'more-specific-quit', moreSpecificQuitHandler

          expect(keymap.handleKeyEvent(keydownEvent('x', target: grandchildNode, ctrlKey: true))).toBeFalsy()
          expect(keymap.handleKeyEvent(keydownEvent('1', target: grandchildNode))).toBeFalsy()
          expect(quitHandler).not.toHaveBeenCalled()
          expect(moreSpecificQuitHandler).not.toHaveBeenCalled()
          expect(closeOtherWindowsHandler).toHaveBeenCalled()
          closeOtherWindowsHandler.reset()

          expect(keymap.handleKeyEvent(keydownEvent('x', target: grandchildNode, ctrlKey: true))).toBeFalsy()
          expect(keymap.handleKeyEvent(keydownEvent('c', target: grandchildNode, ctrlKey: true))).toBeFalsy()
          expect(quitHandler).not.toHaveBeenCalled()
          expect(closeOtherWindowsHandler).not.toHaveBeenCalled()
          expect(moreSpecificQuitHandler).toHaveBeenCalled()

      describe "when there is a complete binding with a less specific selector", ->
        it "favors the more specific partial match", ->

      describe "when there is a complete binding with a more specific selector", ->
        it "favors the more specific complete match", ->

  describe ".bindKeys(name, selector, bindings)", ->
    it "normalizes the key patterns in the hash to put the modifiers in alphabetical order", ->
      fooHandler = jasmine.createSpy('fooHandler')
      fragment.on 'foo', fooHandler
      keymap.bindKeys 'name', '*', 'ctrl-alt-delete': 'foo'
      result = keymap.handleKeyEvent(keydownEvent('delete', ctrlKey: true, altKey: true, target: fragment[0]))
      expect(result).toBe(false)
      expect(fooHandler).toHaveBeenCalled()

      fooHandler.reset()
      keymap.bindKeys 'name', '*', 'ctrl-alt--': 'foo'
      result = keymap.handleKeyEvent(keydownEvent('-', ctrlKey: true, altKey: true, target: fragment[0]))
      expect(result).toBe(false)
      expect(fooHandler).toHaveBeenCalled()

  describe ".remove(name)", ->
    it "removes the binding set with the given selector and bindings", ->
      keymap.add 'nature',
        '.green':
          'ctrl-c': 'cultivate'
        '.brown':
          'ctrl-h': 'harvest'

      expect(keymap.bindingsMatchingElement($$ -> @div class: 'green')).toHaveLength 1
      expect(keymap.bindingsMatchingElement($$ -> @div class: 'brown')).toHaveLength 1

      keymap.remove('nature')

      expect(keymap.bindingsMatchingElement($$ -> @div class: 'green')).toEqual []
      expect(keymap.bindingsMatchingElement($$ -> @div class: 'brown')).toEqual []

  describe ".keystrokeStringForEvent(event)", ->
    describe "when no modifiers are pressed", ->
      it "returns a string that identifies the key pressed", ->
        expect(keymap.keystrokeStringForEvent(keydownEvent('a'))).toBe 'a'
        expect(keymap.keystrokeStringForEvent(keydownEvent('['))).toBe '['
        expect(keymap.keystrokeStringForEvent(keydownEvent('*'))).toBe '*'
        expect(keymap.keystrokeStringForEvent(keydownEvent('left'))).toBe 'left'
        expect(keymap.keystrokeStringForEvent(keydownEvent('\b'))).toBe 'backspace'

    describe "when ctrl, alt or meta is pressed with a non-modifier key", ->
      it "returns a string that identifies the key pressed", ->
        expect(keymap.keystrokeStringForEvent(keydownEvent('a', altKey: true))).toBe 'alt-a'
        expect(keymap.keystrokeStringForEvent(keydownEvent('[', metaKey: true))).toBe 'meta-['
        expect(keymap.keystrokeStringForEvent(keydownEvent('*', ctrlKey: true))).toBe 'ctrl-*'
        expect(keymap.keystrokeStringForEvent(keydownEvent('left', ctrlKey: true, metaKey: true, altKey: true))).toBe 'alt-ctrl-meta-left'

    describe "when shift is pressed when a non-modifer key", ->
      it "returns a string that identifies the key pressed", ->
        expect(keymap.keystrokeStringForEvent(keydownEvent('A', shiftKey: true))).toBe 'A'
        expect(keymap.keystrokeStringForEvent(keydownEvent('{', shiftKey: true))).toBe '{'
        expect(keymap.keystrokeStringForEvent(keydownEvent('left', shiftKey: true))).toBe 'shift-left'
        expect(keymap.keystrokeStringForEvent(keydownEvent('Left', shiftKey: true))).toBe 'shift-left'

  describe ".bindingsMatchingElement(element)", ->
    it "returns the matching bindings for the element", ->
      keymap.bindKeys 'name', '.command-mode', 'c': 'c'
      keymap.bindKeys 'name', '.grandchild-node', 'g': 'g'

      bindings = keymap.bindingsMatchingElement(fragment.find('.grandchild-node'))
      expect(bindings).toHaveLength 2
      expect(bindings[0].command).toEqual "g"
      expect(bindings[1].command).toEqual "c"

    describe "when multiple bindings match a keystroke", ->
      it "only returns bindings that match the most specific selector", ->
        keymap.bindKeys 'name', '.command-mode', 'g': 'command-mode'
        keymap.bindKeys 'name', '.command-mode .grandchild-node', 'g': 'command-and-grandchild-node'
        keymap.bindKeys 'name', '.grandchild-node', 'g': 'grandchild-node'

        bindings = keymap.bindingsMatchingElement(fragment.find('.grandchild-node'))
        expect(bindings).toHaveLength 3
        expect(bindings[0].command).toEqual "command-and-grandchild-node"
