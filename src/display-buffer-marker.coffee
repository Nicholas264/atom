{Range} = require 'text-buffer'
_ = require 'underscore-plus'
{Subscriber} = require 'emissary'
EmitterMixin = require('emissary').Emitter
{Emitter} = require 'event-kit'
Grim = require 'grim'

# Essential: Represents a buffer annotation that remains logically stationary
# even as the buffer changes. This is used to represent cursors, folds, snippet
# targets, misspelled words, and anything else that needs to track a logical
# location in the buffer over time.
#
# ### Head and Tail
#
# Markers always have a *head* and sometimes have a *tail*. If you think of a
# marker as an editor selection, the tail is the part that's stationary and the
# head is the part that moves when the mouse is moved. A marker without a tail
# always reports an empty range at the head position. A marker with a head position
# greater than the tail is in a "normal" orientation. If the head precedes the
# tail the marker is in a "reversed" orientation.
#
# ### Validity
#
# Markers are considered *valid* when they are first created. Depending on the
# invalidation strategy you choose, certain changes to the buffer can cause a
# marker to become invalid, for example if the text surrounding the marker is
# deleted. See {Editor::markBufferRange} for invalidation strategies.
module.exports =
class DisplayBufferMarker
  EmitterMixin.includeInto(this)
  Subscriber.includeInto(this)

  bufferMarkerSubscription: null
  oldHeadBufferPosition: null
  oldHeadScreenPosition: null
  oldTailBufferPosition: null
  oldTailScreenPosition: null
  wasValid: true
  deferredChangeEvents: null

  ###
  Section: Construction and Destruction
  ###

  constructor: ({@bufferMarker, @displayBuffer}) ->
    @emitter = new Emitter
    @id = @bufferMarker.id
    @oldHeadBufferPosition = @getHeadBufferPosition()
    @oldHeadScreenPosition = @getHeadScreenPosition()
    @oldTailBufferPosition = @getTailBufferPosition()
    @oldTailScreenPosition = @getTailScreenPosition()
    @wasValid = @isValid()

    @subscribe @bufferMarker.onDidDestroy => @destroyed()
    @subscribe @bufferMarker.onDidChange (event) => @notifyObservers(event)

  # Essential: Destroys the marker, causing it to emit the 'destroyed' event. Once
  # destroyed, a marker cannot be restored by undo/redo operations.
  destroy: ->
    @bufferMarker.destroy()
    @unsubscribe()

  # Essential: Creates and returns a new {Marker} with the same properties as this
  # marker.
  #
  # * `properties` {Object}
  copy: (properties) ->
    @displayBuffer.getMarker(@bufferMarker.copy(properties).id)

  ###
  Section: Event Subscription
  ###

  # Essential: Invoke the given callback when the state of the marker changes.
  #
  # * `callback` {Function} to be called when the marker changes.
  #   * `event` {Object} with the following keys:
  #     * `oldHeadPosition` {Point} representing the former head position
  #     * `newHeadPosition` {Point} representing the new head position
  #     * `oldTailPosition` {Point} representing the former tail position
  #     * `newTailPosition` {Point} representing the new tail position
  #     * `wasValid` {Boolean} indicating whether the marker was valid before the change
  #     * `isValid` {Boolean} indicating whether the marker is now valid
  #     * `hadTail` {Boolean} indicating whether the marker had a tail before the change
  #     * `hasTail` {Boolean} indicating whether the marker now has a tail
  #     * `oldProperties` {Object} containing the marker's custom properties before the change.
  #     * `newProperties` {Object} containing the marker's custom properties after the change.
  #     * `textChanged` {Boolean} indicating whether this change was caused by a textual change
  #       to the buffer or whether the marker was manipulated directly via its public API.
  #
  # Returns a {Disposable} on which `.dispose()` can be called to unsubscribe.
  onDidChange: (callback) ->
    @emitter.on 'did-change', callback

  # Essential: Invoke the given callback when the marker is destroyed.
  #
  # * `callback` {Function} to be called when the marker is destroyed.
  #
  # Returns a {Disposable} on which `.dispose()` can be called to unsubscribe.
  onDidDestroy: (callback) ->
    @emitter.on 'did-destroy', callback

  on: (eventName) ->
    switch eventName
      when 'changed'
        Grim.deprecate("Use DisplayBufferMarker::onDidChange instead")
      when 'destroyed'
        Grim.deprecate("Use DisplayBufferMarker::onDidDestroy instead")

    EmitterMixin::on.apply(this, arguments)

  ###
  Section: Marker Metadata
  ###

  # Essential: Returns a {Boolean} indicating whether the marker is valid. Markers can be
  # invalidated when a region surrounding them in the buffer is changed.
  isValid: ->
    @bufferMarker.isValid()

  # Essential: Returns a {Boolean} indicating whether the marker has been destroyed. A marker
  # can be invalid without being destroyed, in which case undoing the invalidating
  # operation would restore the marker. Once a marker is destroyed by calling
  # {Marker::destroy}, no undo/redo operation can ever bring it back.
  isDestroyed: ->
    @bufferMarker.isDestroyed()

  # Extended: Returns a {Boolean} indicating whether the head precedes the tail.
  isReversed: ->
    @bufferMarker.isReversed()

  # Extended: Get the invalidation strategy for this marker.
  #
  # Valid values include: `never`, `surround`, `overlap`, `inside`, and `touch`.
  #
  # Returns a {String}.
  getInvalidationStrategy: ->
    @bufferMarker.getInvalidationStrategy()

  # Extended: Returns an {Object} containing any custom properties associated with
  # the marker.
  getProperties: ->
    @bufferMarker.getProperties()
  getAttributes: ->
    deprecate 'Use Marker::getProperties instead'
    @getProperties()

  # Extended: Merges an {Object} containing new properties into the marker's
  # existing properties.
  #
  # * `properties` {Object}
  setProperties: (properties) ->
    @bufferMarker.setProperties(properties)
  setAttributes: (properties) ->
    deprecate 'Use Marker::getProperties instead'
    @setProperties(properties)

  matchesProperties: (attributes) ->
    attributes = @displayBuffer.translateToBufferMarkerParams(attributes)
    @bufferMarker.matchesParams(attributes)
  matchesAttributes: (attributes) ->
    deprecate 'Use Marker::matchesProperties instead'
    @matchesProperties(attributes)

  ###
  Section: Comparing to other markers
  ###

  # Essential: Returns a {Boolean} indicating whether this marker is equivalent to
  # another marker, meaning they have the same range and options.
  #
  # * `other` {Marker} other marker
  isEqual: (other) ->
    return false unless other instanceof @constructor
    @bufferMarker.isEqual(other.bufferMarker)

  # Essential: Compares this marker to another based on their ranges.
  #
  # * `other` {Marker}
  #
  # Returns a {Number}
  compare: (other) ->
    @bufferMarker.compare(other.bufferMarker)

  ###
  Section: Managing the marker's range
  ###

  # Essential: Gets the buffer range of the display marker.
  #
  # Returns a {Range}.
  getBufferRange: ->
    @bufferMarker.getRange()

  # Essential: Modifies the buffer range of the display marker.
  #
  # * `bufferRange` The new {Range} to use
  # * `properties` (optional) {Object} properties to associate with the marker.
  #   * `reversed` {Boolean} If true, the marker will to be in a reversed orientation.
  setBufferRange: (bufferRange, properties) ->
    @bufferMarker.setRange(bufferRange, properties)

  # Essential: Gets the screen range of the display marker.
  #
  # Returns a {Range}.
  getScreenRange: ->
    @displayBuffer.screenRangeForBufferRange(@getBufferRange(), wrapAtSoftNewlines: true)

  # Essential: Modifies the screen range of the display marker.
  #
  # * `screenRange` The new {Range} to use
  # * `properties` (optional) {Object} properties to associate with the marker.
  #   * `reversed` {Boolean} If true, the marker will to be in a reversed orientation.
  setScreenRange: (screenRange, options) ->
    @setBufferRange(@displayBuffer.bufferRangeForScreenRange(screenRange), options)

  # Essential: Retrieves the buffer position of the marker's start. This will always be
  # less than or equal to the result of {DisplayBufferMarker::getEndBufferPosition}.
  #
  # Returns a {Point}.
  getStartBufferPosition: ->
    @bufferMarker.getStartPosition()

  # Essential: Retrieves the screen position of the marker's start. This will always be
  # less than or equal to the result of {DisplayBufferMarker::getEndScreenPosition}.
  #
  # Returns a {Point}.
  getStartScreenPosition: ->
    @displayBuffer.screenPositionForBufferPosition(@getStartBufferPosition(), wrapAtSoftNewlines: true)

  # Essential: Retrieves the buffer position of the marker's end. This will always be
  # greater than or equal to the result of {DisplayBufferMarker::getStartBufferPosition}.
  #
  # Returns a {Point}.
  getEndBufferPosition: ->
    @bufferMarker.getEndPosition()

  # Essential: Retrieves the screen position of the marker's end. This will always be
  # greater than or equal to the result of {DisplayBufferMarker::getStartScreenPosition}.
  #
  # Returns a {Point}.
  getEndScreenPosition: ->
    @displayBuffer.screenPositionForBufferPosition(@getEndBufferPosition(), wrapAtSoftNewlines: true)

  # Extended: Retrieves the buffer position of the marker's head.
  #
  # Returns a {Point}.
  getHeadBufferPosition: ->
    @bufferMarker.getHeadPosition()

  # Extended: Sets the buffer position of the marker's head.
  #
  # * `screenRange` The new {Point} to use
  # * `properties` (optional) {Object} properties to associate with the marker.
  setHeadBufferPosition: (bufferPosition, properties) ->
    @bufferMarker.setHeadPosition(bufferPosition, properties)

  # Extended: Retrieves the screen position of the marker's head.
  #
  # Returns a {Point}.
  getHeadScreenPosition: ->
    @displayBuffer.screenPositionForBufferPosition(@getHeadBufferPosition(), wrapAtSoftNewlines: true)

  # Extended: Sets the screen position of the marker's head.
  #
  # * `screenRange` The new {Point} to use
  # * `properties` (optional) {Object} properties to associate with the marker.
  setHeadScreenPosition: (screenPosition, properties) ->
    screenPosition = @displayBuffer.clipScreenPosition(screenPosition, properties)
    @setHeadBufferPosition(@displayBuffer.bufferPositionForScreenPosition(screenPosition, properties))

  # Extended: Retrieves the buffer position of the marker's tail.
  #
  # Returns a {Point}.
  getTailBufferPosition: ->
    @bufferMarker.getTailPosition()

  # Extended: Sets the buffer position of the marker's tail.
  #
  # * `screenRange` The new {Point} to use
  # * `properties` (optional) {Object} properties to associate with the marker.
  setTailBufferPosition: (bufferPosition) ->
    @bufferMarker.setTailPosition(bufferPosition)

  # Extended: Retrieves the screen position of the marker's tail.
  #
  # Returns a {Point}.
  getTailScreenPosition: ->
    @displayBuffer.screenPositionForBufferPosition(@getTailBufferPosition(), wrapAtSoftNewlines: true)

  # Extended: Sets the screen position of the marker's tail.
  #
  # * `screenRange` The new {Point} to use
  # * `properties` (optional) {Object} properties to associate with the marker.
  setTailScreenPosition: (screenPosition, options) ->
    screenPosition = @displayBuffer.clipScreenPosition(screenPosition, options)
    @setTailBufferPosition(@displayBuffer.bufferPositionForScreenPosition(screenPosition, options))

  # Extended: Returns a {Boolean} indicating whether the marker has a tail.
  hasTail: ->
    @bufferMarker.hasTail()

  # Extended: Plants the marker's tail at the current head position. After calling
  # the marker's tail position will be its head position at the time of the
  # call, regardless of where the marker's head is moved.
  #
  # * `properties` (optional) {Object} properties to associate with the marker.
  plantTail: ->
    @bufferMarker.plantTail()

  # Extended: Removes the marker's tail. After calling the marker's head position
  # will be reported as its current tail position until the tail is planted
  # again.
  #
  # * `properties` (optional) {Object} properties to associate with the marker.
  clearTail: (properties) ->
    @bufferMarker.clearTail(properties)

  ###
  Section: Private utility methods
  ###

  # Returns a {String} representation of the marker
  inspect: ->
    "DisplayBufferMarker(id: #{@id}, bufferRange: #{@getBufferRange()})"

  destroyed: ->
    delete @displayBuffer.markers[@id]
    @emit 'destroyed'
    @emitter.emit 'did-destroy'
    @emitter.dispose()

  notifyObservers: ({textChanged}) ->
    textChanged ?= false

    newHeadBufferPosition = @getHeadBufferPosition()
    newHeadScreenPosition = @getHeadScreenPosition()
    newTailBufferPosition = @getTailBufferPosition()
    newTailScreenPosition = @getTailScreenPosition()
    isValid = @isValid()

    return if _.isEqual(isValid, @wasValid) and
      _.isEqual(newHeadBufferPosition, @oldHeadBufferPosition) and
      _.isEqual(newHeadScreenPosition, @oldHeadScreenPosition) and
      _.isEqual(newTailBufferPosition, @oldTailBufferPosition) and
      _.isEqual(newTailScreenPosition, @oldTailScreenPosition)

    changeEvent = {
      @oldHeadScreenPosition, newHeadScreenPosition,
      @oldTailScreenPosition, newTailScreenPosition,
      @oldHeadBufferPosition, newHeadBufferPosition,
      @oldTailBufferPosition, newTailBufferPosition,
      textChanged,
      isValid
    }

    if @deferredChangeEvents?
      @deferredChangeEvents.push(changeEvent)
    else
      @emit 'changed', changeEvent
      @emitter.emit 'did-change', changeEvent

    @oldHeadBufferPosition = newHeadBufferPosition
    @oldHeadScreenPosition = newHeadScreenPosition
    @oldTailBufferPosition = newTailBufferPosition
    @oldTailScreenPosition = newTailScreenPosition
    @wasValid = isValid

  pauseChangeEvents: ->
    @deferredChangeEvents = []

  resumeChangeEvents: ->
    if deferredChangeEvents = @deferredChangeEvents
      @deferredChangeEvents = null

      for event in deferredChangeEvents
        @emit 'changed', event
        @emitter.emit 'did-change', event

  getPixelRange: ->
    @displayBuffer.pixelRangeForScreenRange(@getScreenRange(), false)
