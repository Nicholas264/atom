const {TerminalReporter} = require('jasmine-tagged')

class JasmineTerminalReporter extends TerminalReporter {
  fullDescription (spec) {
    let fullDescription = spec.description
    let currentSuite = spec.suite
    while (currentSuite) {
      fullDescription = currentSuite.description + ' > ' + fullDescription
      currentSuite = currentSuite.parentSuite
    }
    return fullDescription
  }

  reportSpecStarting (spec) {
    this.print_(this.fullDescription(spec) + ' ')
  }

  reportSpecResults (spec) {
    const result = spec.results()
    let msg = ''
    if (result.skipped) {
      msg = this.stringWithColor_(this.fullDescription(spec) + ' [skip]', this.color_.ignore())
    } else if (result.passed()) {
      msg = this.stringWithColor_('[pass]', this.color_.pass())
    } else {
      msg = this.stringWithColor_('[FAIL]', this.color_.fail())
      this.addFailureToFailures_(spec)
    }
    this.printLine_(msg)
  }
}

module.exports = { JasmineTerminalReporter }
