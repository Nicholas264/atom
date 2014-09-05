CommandRegistry = require '../src/command-registry'

describe "CommandRegistry", ->
  [registry, parent, child, grandchild] = []

  beforeEach ->
    parent = document.createElement("div")
    child = document.createElement("div")
    grandchild = document.createElement("div")
    parent.classList.add('parent')
    child.classList.add('child')
    grandchild.classList.add('grandchild')
    child.appendChild(grandchild)
    parent.appendChild(child)
    document.querySelector('#jasmine-content').appendChild(parent)

    registry = new CommandRegistry(parent)

  it "invokes callbacks with selectors matching the target", ->
    called = false
    registry.add 'command', '.grandchild', (event) ->
      expect(this).toBe grandchild
      expect(event.type).toBe 'command'
      expect(event.eventPhase).toBe Event.BUBBLING_PHASE
      expect(event.target).toBe grandchild
      expect(event.currentTarget).toBe grandchild
      called = true

    grandchild.dispatchEvent(new CustomEvent('command', bubbles: true))
    expect(called).toBe true

  it "invokes callbacks with selectors matching ancestors of the target", ->
    calls = []

    registry.add 'command', '.child', (event) ->
      expect(this).toBe child
      expect(event.target).toBe grandchild
      expect(event.currentTarget).toBe child
      calls.push('child')

    registry.add 'command', '.parent', (event) ->
      expect(this).toBe parent
      expect(event.target).toBe grandchild
      expect(event.currentTarget).toBe parent
      calls.push('parent')

    grandchild.dispatchEvent(new CustomEvent('command', bubbles: true))
    expect(calls).toEqual ['child', 'parent']

  it "orders multiple matching listeners for an element by selector specificity", ->
    child.classList.add('foo', 'bar')
    calls = []

    registry.add 'command', '.foo.bar', -> calls.push('.foo.bar')
    registry.add 'command', '.foo', -> calls.push('.foo')
    registry.add 'command', '.bar', -> calls.push('.bar') # specificity ties favor commands added later, like CSS

    grandchild.dispatchEvent(new CustomEvent('command', bubbles: true))
    expect(calls).toEqual ['.foo.bar', '.bar', '.foo']

  it "stops bubbling through ancestors when .stopPropagation() is called on the event", ->
    calls = []

    registry.add 'command', '.parent', -> calls.push('parent')
    registry.add 'command', '.child', -> calls.push('child-2')
    registry.add 'command', '.child', (event) -> calls.push('child-1'); event.stopPropagation()

    grandchild.dispatchEvent(new CustomEvent('command', bubbles: true))
    expect(calls).toEqual ['child-1', 'child-2']
