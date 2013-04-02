fs = require 'fs-utils'
PEG = require 'pegjs'

module.exports =
class CommandInterpreter
  constructor: (@project) ->

  eval: (string, activeEditSession) ->
    @parser ?= PEG.buildParser(fs.read(require.resolve 'command-panel/lib/commands.pegjs'))
    compositeCommand = @parser.parse(string)
    @lastRelativeAddress = compositeCommand if compositeCommand.isRelativeAddress()
    compositeCommand.execute(@project, activeEditSession)

  repeatRelativeAddress: (activeEditSession, {reverse}={}) ->
    return unless @lastRelativeAddress
    reverse ?= false
    previousSelectionRange = activeEditSession.getSelection().getBufferRange()
    address = if reverse then @lastRelativeAddress.reverse() else @lastRelativeAddress

    address.execute(@project, activeEditSession).done ->
      currentSelectionRange = activeEditSession.getSelection().getBufferRange()
      $native.beep() if previousSelectionRange.isEqual(currentSelectionRange)
