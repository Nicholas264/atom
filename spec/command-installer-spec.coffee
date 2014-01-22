{fs} = require 'atom'
path = require 'path'
temp = require 'temp'
installer = require '../src/command-installer'

describe "install(commandPath, callback)", ->
  directory = path.join(temp.dir, 'install-atom-command', 'atom')
  commandPath = path.join(directory, 'source')
  destinationPath = path.join(directory, 'bin', 'source')

  beforeEach ->
    spyOn(installer, 'getInstallDirectory').andReturn directory
    fs.removeSync(directory) if fs.existsSync(directory)

  describe "on #darwin", ->
    it "symlinks the command and makes it executable", ->
      fs.writeFileSync(commandPath, 'test')
      expect(fs.isFileSync(commandPath)).toBeTruthy()
      expect(fs.isExecutableSync(commandPath)).toBeFalsy()
      expect(fs.isFileSync(destinationPath)).toBeFalsy()

      installDone = false
      installError = null
      installer.install commandPath, (error) ->
        installDone = true
        installError = error

      waitsFor -> installDone

      runs ->
        expect(installError).toBeNull()
        expect(fs.isFileSync(destinationPath)).toBeTruthy()
        expect(fs.realpathSync(destinationPath)).toBe fs.realpathSync(commandPath)
        expect(fs.isExecutableSync(destinationPath)).toBeTruthy()
