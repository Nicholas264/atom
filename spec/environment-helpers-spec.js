/** @babel */
/* eslint-env jasmine */

import child_process from 'child_process'
import updateProcessEnv from '../src/update-process-env'
import dedent from 'dedent'

describe('updateProcessEnv(launchEnv)', function () {
  let originalProcessEnv, originalProcessPlatform

  beforeEach(function () {
    originalProcessEnv = process.env
    originalProcessPlatform = process.platform
    process.env = {}
  })

  afterEach(function () {
    process.env = originalProcessEnv
    process.platform = originalProcessPlatform
  })

  describe('when the launch environment appears to come from a shell', function () {
    it('updates process.env to match the launch environment', function () {
      process.env = {
        WILL_BE_DELETED: 'hi',
        NODE_ENV: 'the-node-env',
        NODE_PATH: '/the/node/path',
      }
      const initialProcessEnv = process.env

      updateProcessEnv({PWD: '/the/dir', KEY1: 'value1', KEY2: 'value2'})
      expect(process.env).toEqual({
        PWD: '/the/dir',
        KEY1: 'value1',
        KEY2: 'value2',
        NODE_ENV: 'the-node-env',
        NODE_PATH: '/the/node/path',
      })

      // See #11302. On Windows, `process.env` is a magic object that offers
      // case-insensitive environment variable matching, so we cannot replace it
      // with another object.
      expect(process.env).toBe(initialProcessEnv)
    })
  })

  describe('when the launch environment does not come from a shell', function () {
    describe('on osx', function () {
      it('updates process.env to match the environment in the user\'s login shell', function () {
        process.platform = 'darwin'
        process.env.SHELL = '/my/custom/bash'

        spyOn(child_process, 'spawnSync').andReturn({
          stdout: dedent`
            FOO=BAR=BAZ=QUUX
            TERM=xterm-something
            PATH=/usr/bin:/bin:/usr/sbin:/sbin:/crazy/path
          `
        })

        updateProcessEnv(process.env)
        expect(child_process.spawnSync.mostRecentCall.args[0]).toBe('/my/custom/bash')
        expect(process.env).toEqual({
          FOO: 'BAR=BAZ=QUUX',
          TERM: 'xterm-something',
          PATH: '/usr/bin:/bin:/usr/sbin:/sbin:/crazy/path'
        })
      })
    })

    describe('not on osx', function () {
      it('does not update process.env', function () {
        process.platform = 'win32'
        spyOn(child_process, 'spawnSync')
        process.env = {FOO: 'bar'}

        updateProcessEnv(process.env)
        expect(child_process.spawnSync).not.toHaveBeenCalled()
        expect(process.env).toEqual({FOO: 'bar'})
      })
    })
  })
})
