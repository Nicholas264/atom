# This class represents a gutter other than the 'line-numbers' gutter.
# The contents of this gutter may be specified by Decorations.

# TODO (jssln) Remove these (testing-only).
TEMP_MIN_WIDTH = 25
TEMP_DECOR_WIDTH = '50px'
TEMP_DECOR_BACKGROUND = 'white'

module.exports =
class CustomGutterComponent

  constructor: ({@name}) ->
    @decorationNodesById = {}
    @decorationItemsById = {}

    @domNode = document.createElement('div')
    @domNode.classList.add('gutter')
    @domNode.setAttribute('gutter-name', @name)
    @decorationsNode = document.createElement('div')
    @decorationsNode.classList.add('custom-decorations')
    @domNode.appendChild(@decorationsNode)

    @domNode.style['width'] = '' + TEMP_MIN_WIDTH + 'px'

  getDomNode: ->
    @domNode

  getName: ->
    @name

  updateSync: (state) ->
    gutterProps = state.lineNumberGutter
    decorationState = state.gutters.customDecorations[@getName()]
    @oldState ?= {}

    # TODO (jessicalin) Factor this out (also in LineNumberGutterComponent).
    # Also, set backgroundColor?
    if gutterProps.scrollHeight isnt @oldState.scrollHeight
      @decorationsNode.style.height = gutterProps.scrollHeight + 'px'
      @oldState.scrollHeight = gutterProps.scrollHeight

    if gutterProps.scrollTop isnt @oldState.scrollTop
      @decorationsNode.style['-webkit-transform'] = "translate3d(0px, #{-gutterProps.scrollTop}px, 0px)"
      @oldState.scrollTop = gutterProps.scrollTop

    return if !decorationState

    updatedDecorationIds = new Set
    for decorationId, decorationInfo of decorationState
      updatedDecorationIds.add(decorationId)
      existingDecoration = @decorationNodesById[decorationId]
      if existingDecoration
        @updateDecorationHTML(existingDecoration, decorationId, decorationInfo)
      else
        newNode = @buildDecorationHTML(decorationId, decorationInfo)
        @decorationNodesById[decorationId] = newNode
        @decorationsNode.appendChild(newNode)

    for decorationId, decorationNode of @decorationNodesById
      if !updatedDecorationIds.has(decorationId)
        decorationNode.remove()
        delete @decorationNodesById[decorationId]
        delete @decorationItemsById[decorationId]

  ###
  Section: Private Methods
  ###

  # Builds and returns an HTMLElement to represent the specified decoration.
  buildDecorationHTML: (decorationId, decorationInfo) ->
    newNode = document.createElement('div')
    newNode.classList.add('decoration')
    newNode.style.top = decorationInfo.top + 'px'
    newNode.style.height = decorationInfo.height + 'px'
    newNode.style.position = 'absolute'
    newNode.style['background-color'] = TEMP_DECOR_BACKGROUND
    newNode.style.width = TEMP_DECOR_WIDTH
    if decorationInfo.class
      newNode.classList.add(decorationInfo.class)
    @setDecorationItem(decorationInfo.item, decorationInfo.height, decorationId, newNode)
    newNode

  # Updates the existing HTMLNode with the new decoration info. Attempts to
  # minimize changes to the DOM.
  updateDecorationHTML: (existingNode, decorationId, newDecorationInfo) ->
    if existingNode.style.top isnt newDecorationInfo.top + 'px'
      existingNode.style.top = newDecorationInfo.top + 'px'

    if existingNode.style.height isnt newDecorationInfo.height + 'px'
      existingNode.style.height = newDecorationInfo.height + 'px'

    if newDecorationInfo.class and !existingNode.classList.contains(newDecorationInfo.class)
      existingNode.className = 'decoration'
      existingNode.classList.add(newDecorationInfo.class)
    else if !newDecorationInfo.class
      existingNode.className = 'decoration'

    @setDecorationItem(newDecorationInfo.item, newDecorationInfo.height, decorationId, existingNode)

  # Sets the decorationItem on the decorationNode.
  # If `decorationItem` is undefined, the decorationNode's child item will be cleared.
  setDecorationItem: (newItem, decorationHeight, decorationId, decorationNode) ->
    if newItem isnt @decorationItemsById[decorationId]
      while decorationNode.firstChild
        decorationNode.removeChild(decorationNode.firstChild)
      delete @decorationItemsById[decorationId]

      if newItem
        # `item` should be either an HTMLElement or a space-pen View.
        newItemNode = null
        if newItem instanceof HTMLElement
          newItemNode = newItem
        else
          newItemNode = newItem.element

        newItemNode.style.height = decorationHeight + 'px'
        decorationNode.appendChild(newItemNode)
        @decorationItemsById[decorationId] = newItem
