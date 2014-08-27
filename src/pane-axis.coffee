{Model} = require 'theorist'
{Emitter, CompositeDisposable} = require 'event-kit'
{flatten} = require 'underscore-plus'
Serializable = require 'serializable'

PaneRowView = null
PaneColumnView = null

module.exports =
class PaneAxis extends Model
  atom.deserializers.add(this)
  Serializable.includeInto(this)

  constructor: ({@container, @orientation, children}) ->
    @emitter = new Emitter
    @subscriptionsByChild = new WeakMap
    @subscriptions = new CompositeDisposable
    @children = []
    if children?
      @addChild(child) for child in children

  deserializeParams: (params) ->
    {container} = params
    params.children = params.children.map (childState) -> atom.deserializers.deserialize(childState, {container})
    params

  serializeParams: ->
    children: @children.map (child) -> child.serialize()
    orientation: @orientation

  getViewClass: ->
    if @orientation is 'vertical'
      PaneColumnView ?= require './pane-column-view'
    else
      PaneRowView ?= require './pane-row-view'

  getChildren: -> @children.slice()

  getPanes: ->
    flatten(@children.map (child) -> child.getPanes())

  onDidAddChild: (fn) ->
    @emitter.on 'did-add-child', fn

  onDidRemoveChild: (fn) ->
    @emitter.on 'did-remove-child', fn

  onDidReplaceChild: (fn) ->
    @emitter.on 'did-replace-child', fn

  onDidDestroy: (fn) ->
    @emitter.on 'did-destroy'

  addChild: (child, index=@children.length) ->
    child.parent = this
    child.container = @container

    @subscribeToChild(child)

    @children.splice(index, 0, child)
    @emitter.emit 'did-add-child', {child, index}

  removeChild: (child, replacing=false) ->
    index = @children.indexOf(child)
    throw new Error("Removing non-existent child") if index is -1

    @unsubscribeFromChild(child)

    @children.splice(index, 1)
    @emitter.emit 'did-remove-child', {child, index}
    @reparentLastChild() if not replacing and @children.length < 2

  replaceChild: (oldChild, newChild) ->
    @unsubscribeFromChild(oldChild)
    @subscribeToChild(newChild)

    newChild.parent = this
    newChild.container = @container

    index = @children.indexOf(oldChild)
    @children.splice(index, 1, newChild)
    @emitter.emit 'did-replace-child', {oldChild, newChild, index}

  insertChildBefore: (currentChild, newChild) ->
    index = @children.indexOf(currentChild)
    @addChild(newChild, index)

  insertChildAfter: (currentChild, newChild) ->
    index = @children.indexOf(currentChild)
    @addChild(newChild, index + 1)

  reparentLastChild: ->
    @parent.replaceChild(this, @children[0])
    @destroy()

  subscribeToChild: (child) ->
    subscription = child.onDidDestroy => @removeChild(child)
    @subscriptionsByChild.set(child, subscription)
    @subscriptions.add(child)

  unsubscribeFromChild: (child) ->
    subscription = @subscriptionsByChild.get(child)
    @subscriptions.remove(child)
    subscription.dispose()

  destroyed: ->
    @emitter.emit 'did-destroy'
    @emitter.dispose()
