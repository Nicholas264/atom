# Start the crash reporter before anything else.
require('crash-reporter').start(productName: 'Atom', companyName: 'GitHub')

try
  path = require 'path'
  ipc = require 'ipc'
  remote = require 'remote'
  {getWindowLoadSettings} = require './window-load-settings-helpers'
  AtomEnvironment = require '../src/atom-environment'

  # Show window synchronously so a focusout doesn't fire on input elements
  # that are focused in the very first spec run.
  remote.getCurrentWindow().show() unless getWindowLoadSettings().headless

  window.addEventListener 'keydown', (event) ->
    # Reload: cmd-r / ctrl-r
    if (event.metaKey or event.ctrlKey) and event.keyCode is 82
      ipc.send('call-window-method', 'restart')

    # Toggle Dev Tools: cmd-alt-i / ctrl-alt-i
    if (event.metaKey or event.ctrlKey) and event.altKey and event.keyCode is 73
      ipc.send('call-window-method', 'toggleDevTools')

    # Reload: cmd-w / ctrl-w
    if (event.metaKey or event.ctrlKey) and event.keyCode is 87
      ipc.send('call-window-method', 'close')

  # Add 'exports' to module search path.
  exportsPath = path.join(getWindowLoadSettings().resourcePath, 'exports')
  require('module').globalPaths.push(exportsPath)
  process.env.NODE_PATH = exportsPath # Set NODE_PATH env variable since tasks may need it.

  # Shim process stdout and stderr so that they can be logged out to console.
  process.stdout = remote.process.stdout
  process.stderr = remote.process.stderr

  document.title = "Spec Suite"

  legacyTestRunner = require(getWindowLoadSettings().legacyTestRunnerPath)
  testRunner = require(getWindowLoadSettings().testRunnerPath)
  testRunner({
    logFile: getWindowLoadSettings().logFile
    headless: getWindowLoadSettings().headless
    testPaths: getWindowLoadSettings().testPaths
    buildAtomEnvironment: -> new AtomEnvironment
    legacyTestRunner: legacyTestRunner
  })
catch error
  if getWindowLoadSettings().headless
    console.error(error.stack ? error)
    remote.require('app').emit('will-exit')
    remote.process.exit(status)
  else
    throw error
