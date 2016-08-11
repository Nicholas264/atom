/** @babel */

import dedent from 'dedent'
import electron from 'electron'
import fs from 'fs-plus'
import path from 'path'
import temp from 'temp'
import AtomApplication from '../../src/main-process/atom-application'
import parseCommandLine from '../../src/main-process/parse-command-line'

const ATOM_RESOURCE_PATH = path.resolve(__dirname, '..', '..')

describe('AtomApplication', function () {
  let originalAtomHome, atomApplicationsToDestroy

  beforeEach(function () {
    originalAtomHome = process.env.ATOM_HOME
    process.env.ATOM_HOME = makeTempDir('atom-home')
    // Symlinking the compile cache into the temporary home dir makes the windows load much faster
    fs.symlinkSync(path.join(originalAtomHome, 'compile-cache'), path.join(process.env.ATOM_HOME, 'compile-cache'))
    atomApplicationsToDestroy = []
  })

  afterEach(function () {
    process.env.ATOM_HOME = originalAtomHome
    for (let atomApplication of atomApplicationsToDestroy) {
      atomApplication.destroy()
    }
  })

  describe('openWithOptions', function () {
    this.timeout(20000)

    it('can open to a specific line number of a file', async function () {
      const filePath = path.join(makeTempDir(), 'new-file')
      fs.writeFileSync(filePath, '1\n2\n3\n4\n')
      const atomApplication = buildAtomApplication()

      const window = atomApplication.openWithOptions(parseCommandLine([filePath + ':3']))
      await window.loadedPromise

      const cursorRow = await evalInWebContents(window.browserWindow.webContents, function (sendBackToMainProcess) {
        atom.workspace.onDidChangeActivePaneItem(function (textEditor) {
          sendBackToMainProcess(textEditor.getCursorBufferPosition().row)
        })
      })

      assert.equal(cursorRow, 2)
    })

    it('can open to a specific line and column of a file', async function () {
      const filePath = path.join(makeTempDir(), 'new-file')
      fs.writeFileSync(filePath, '1\n2\n3\n4\n')
      const atomApplication = buildAtomApplication()

      const window = atomApplication.openWithOptions(parseCommandLine([filePath + ':2:2']))
      await window.loadedPromise

      const cursorPosition = await evalInWebContents(window.browserWindow.webContents, function (sendBackToMainProcess) {
        atom.workspace.onDidChangeActivePaneItem(function (textEditor) {
          sendBackToMainProcess(textEditor.getCursorBufferPosition())
        })
      })

      assert.deepEqual(cursorPosition, {row: 1, column: 1})
    })

    it('removes all trailing whitespace and colons from the specified path', async function () {
      let filePath = path.join(makeTempDir(), 'new-file')
      fs.writeFileSync(filePath, '1\n2\n3\n4\n')
      const atomApplication = buildAtomApplication()

      const window = atomApplication.openWithOptions(parseCommandLine([filePath + '::   ']))
      await window.loadedPromise

      const openedPath = await evalInWebContents(window.browserWindow.webContents, function (sendBackToMainProcess) {
        atom.workspace.onDidChangeActivePaneItem(function (textEditor) {
          sendBackToMainProcess(textEditor.getPath())
        })
      })

      assert.equal(openedPath, filePath)
    })

    it('positions new windows at an offset distance from the previous window', async function () {
      const atomApplication = buildAtomApplication()

      const window1 = atomApplication.openWithOptions(parseCommandLine([]))
      await window1.loadedPromise
      window1.browserWindow.setBounds({width: 400, height: 400, x: 0, y: 0})

      const window2 = atomApplication.openWithOptions(parseCommandLine([]))
      await window2.loadedPromise

      window1Dimensions = window1.getDimensions()
      window2Dimensions = window2.getDimensions()
      assert.isAbove(window2Dimensions.x, window1Dimensions.x)
      assert.isAbove(window2Dimensions.y, window1Dimensions.y)
    })
  })

  function buildAtomApplication () {
    const atomApplication = new AtomApplication({
      resourcePath: ATOM_RESOURCE_PATH,
      atomHomeDirPath: process.env.ATOM_HOME
    })
    atomApplicationsToDestroy.push(atomApplication)
    return atomApplication
  }
  function makeTempDir (name) {
    return fs.realpathSync(temp.mkdirSync(name))
  }

  let channelIdCounter = 0
  function evalInWebContents (webContents, source) {
    const channelId = 'eval-result-' + channelIdCounter++
    return new Promise(function (resolve) {
      electron.ipcMain.on(channelId, receiveResult)

      function receiveResult (event, result) {
        electron.ipcMain.removeListener('eval-result', receiveResult)
        resolve(result)
      }

      webContents.executeJavaScript(dedent`
        function sendBackToMainProcess (result) {
          require('electron').ipcRenderer.send('${channelId}', result)
        }
        (${source})(sendBackToMainProcess)
      `)
    })
  }
})
