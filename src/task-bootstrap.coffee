{userAgent, taskPath} = process.env
handler = null

setupGlobals = ->
  global.attachEvent = ->
  console =
    warn: -> emit 'task:warn', arguments...
    log: -> emit 'task:log', arguments...
    error: -> emit 'task:error', arguments...
  global.__defineGetter__ 'console', -> console

  global.document =
    createElement: ->
      setAttribute: ->
      getElementsByTagName: -> []
      appendChild: ->
    documentElement:
      insertBefore: ->
      removeChild: ->
    getElementById: -> {}
    createComment: -> {}
    createDocumentFragment: -> {}

  global.emit = (event, args...) ->
    process.send({event, args})
  global.navigator = {userAgent}
  global.window = global

handleEvents = ->
  process.on 'uncaughtException', (error) -> console.error(error.message)
  process.on 'message', ({args}) ->
    result = handler(args...)
    emit('task:completed', result)

setupGlobals()
handleEvents()
handler = require(taskPath)
