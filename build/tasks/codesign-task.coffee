module.exports = (grunt) ->
  {spawn} = require('./task-helpers')(grunt)

  grunt.registerTask 'codesign', 'Codesign the app', ->
    done = @async()

    if process.env.XCODE_KEYCHAIN
      unlockKeychain (error) ->
        if error?
          done(error)
        else
          signApp(done)
    else
      signApp(done)

  unlockKeychain = (callback) ->
    cmd = 'security'
    args = ['-p', process.env.XCODE_KEYCHAIN_PASSWORD, process.env.XCODE_KEYCHAIN]
    spawn {cmd, args}, (error) -> callback(error)

  signApp = (callback) ->
    cmd = 'codesign'
    args = ['-f', '-v', '-s', 'Developer ID Application: GitHub', grunt.config.get('atom.shellAppDir')]
    spawn {cmd, args}, (error) -> done(error)
