fs = require 'fs'
path = require 'path'

async = require 'async'

module.exports = (grunt) ->
  {spawn} = require('./task-helpers')(grunt)

  grunt.registerTask 'run-specs', 'Run the specs', ->
    passed = true
    done = @async()
    atomPath = path.resolve('atom.sh')
    apmPath = path.resolve('node_modules/.bin/apm')

    queue = async.queue (packagePath, callback) ->
      options =
        cmd: apmPath
        args: ['test', '--path', atomPath]
        opts:
          cwd: packagePath
      grunt.log.writeln("Launching #{path.basename(packagePath)} specs.")
      spawn options, (error, results, code) ->
        passed = passed and code is 0
        callback()

    modulesDirectory = path.resolve('node_modules')
    for packageDirectory in fs.readdirSync(modulesDirectory)
      packagePath = path.join(modulesDirectory, packageDirectory)
      continue unless grunt.file.isDir(path.join(packagePath, 'spec'))
      try
        {engines} = grunt.file.readJSON(path.join(packagePath, 'package.json')) ? {}
        queue.push(packagePath) if engines.atom?

    queue.concurrency = 1
    queue.drain = -> done(passed)
