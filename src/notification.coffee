{Emitter} = require 'event-kit'

# Experimental: This will likely change, do not use.
module.exports =
class Notification
  constructor: (@type, @message, @options={}) ->
    @emitter = new Emitter
    @timestamp = new Date()
    @dismissed = true
    @dismissed = false if @isDismissable()

  onDidDismiss: (callback) ->
    @emitter.on 'did-dismiss', callback

  getOptions: -> @options

  getType: -> @type

  getMessage: -> @message

  getTimestamp: -> @timestamp

  getDetail: -> @options.detail

  isEqual: (other) ->
    @getMessage() == other.getMessage() \
      and @getType() == other.getType() \
      and @getDetail() == other.getDetail()

  dismiss: ->
    return unless @isDismissable() and not @isDismissed()
    @dismissed = true
    @emitter.emit 'did-dismiss'

  isDismissed: -> @dismissed

  isDismissable: -> !!@options.dismissable

  getIcon: ->
    return @options.icon if @options.icon?
    switch @type
      when 'fatal' then 'bug'
      when 'error' then 'flame'
      when 'warning' then 'alert'
      when 'info' then 'info'
      when 'success' then 'check'
