fs = require 'fs'

module.exports.runSpecSuite = (specSuite, logFile, logErrors=true) ->
  {$, $$} = require 'atom'
  window[key] = value for key, value of require '../vendor/jasmine'

  require 'jasmine-focused'
  require 'jasmine-tagged'

  TimeReporter = require './time-reporter'
  timeReporter = new TimeReporter()

  logStream = fs.openSync(logFile, 'w') if logFile?
  log = (str) ->
    if logStream?
      fs.writeSync(logStream, str)
    else
      process.stderr.write(str)

  if atom.getLoadSettings().exitWhenDone
    {jasmineNode} = require 'jasmine-node/lib/jasmine-node/reporter'
    reporter = new jasmineNode.TerminalReporter
      print: (str) ->
        log(str)
      onComplete: (runner) ->
        log('\n')
        timeReporter.logLongestSuites 10, (line) -> log("#{line}\n")
        log('\n')
        timeReporter.logLongestSpecs 10, (line) -> log("#{line}\n")
        fs.closeSync(logStream) if logStream?
        atom.exit(runner.results().failedCount > 0 ? 1 : 0)
  else
    AtomReporter = require './atom-reporter'
    reporter = new AtomReporter()

  require specSuite

  jasmineEnv = jasmine.getEnv()
  jasmineEnv.addReporter(reporter)
  jasmineEnv.addReporter(timeReporter)
  jasmineEnv.setIncludedTags([process.platform])

  $('body').append $$ -> @div id: 'jasmine-content'

  jasmineEnv.execute()
