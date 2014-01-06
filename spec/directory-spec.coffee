Directory = require '../src/directory'
{fs} = require 'atom'
path = require 'path'

describe "Directory", ->
  directory = null

  beforeEach ->
    directory = new Directory(path.join(__dirname, 'fixtures'))

  afterEach ->
    directory.off()

  describe "when the contents of the directory change on disk", ->
    temporaryFilePath = null

    beforeEach ->
      temporaryFilePath = path.join(__dirname, 'fixtures', 'temporary')
      fs.removeSync(temporaryFilePath) if fs.existsSync(temporaryFilePath)

    afterEach ->
      fs.removeSync(temporaryFilePath) if fs.existsSync(temporaryFilePath)

    it "triggers 'contents-changed' event handlers", ->
      changeHandler = null

      runs ->
        changeHandler = jasmine.createSpy('changeHandler')
        directory.on 'contents-changed', changeHandler
        fs.writeFileSync(temporaryFilePath, '')

      waitsFor "first change", -> changeHandler.callCount > 0

      runs ->
        changeHandler.reset()
        fs.removeSync(temporaryFilePath)

      waitsFor "second change", -> changeHandler.callCount > 0

  describe "when the directory unsubscribes from events", ->
    temporaryFilePath = null

    beforeEach ->
      temporaryFilePath = path.join(directory.path, 'temporary')
      fs.removeSync(temporaryFilePath) if fs.existsSync(temporaryFilePath)

    afterEach ->
      fs.removeSync(temporaryFilePath) if fs.existsSync(temporaryFilePath)

    it "no longer triggers events", ->
      changeHandler = null

      runs ->
        changeHandler = jasmine.createSpy('changeHandler')
        directory.on 'contents-changed', changeHandler
        fs.writeFileSync(temporaryFilePath, '')

      waitsFor "change event", -> changeHandler.callCount > 0

      runs ->
        changeHandler.reset()
        directory.off()
      waits 20

      runs -> fs.removeSync(temporaryFilePath)
      waits 20
      runs -> expect(changeHandler.callCount).toBe 0

  describe "on #darwin or #linux", ->
    it "includes symlink information about entries", ->
      entries = directory.getEntriesSync()
      for entry in entries
        name = entry.getBaseName()
        if name is 'symlink-to-dir' or name is 'symlink-to-file'
          expect(entry.symlink).toBeTruthy()
        else
          expect(entry.symlink).toBeFalsy()

      callback = jasmine.createSpy('getEntries')
      directory.getEntries(callback)

      waitsFor -> callback.callCount is 1

      runs ->
        entries = callback.mostRecentCall.args[0]
        for entry in entries
          name = entry.getBaseName()
          if name is 'symlink-to-dir' or name is 'symlink-to-file'
            expect(entry.symlink).toBeTruthy()
          else
            expect(entry.symlink).toBeFalsy()

  describe ".relativize(path)", ->
    describe "on #darwin or #linux", ->
      it "returns a relative path based on the directory's path", ->
        absolutePath = directory.getPath()
        expect(directory.relativize(absolutePath)).toBe ''
        expect(directory.relativize(path.join(absolutePath, "b"))).toBe "b"
        expect(directory.relativize(path.join(absolutePath, "b/file.coffee"))).toBe "b/file.coffee"
        expect(directory.relativize(path.join(absolutePath, "file.coffee"))).toBe "file.coffee"

      it "returns a relative path based on the directory's symlinked source path", ->
        symlinkPath = path.join(__dirname, 'fixtures', 'symlink-to-dir')
        symlinkDirectory = new Directory(symlinkPath)
        realFilePath = require.resolve('./fixtures/dir/a')
        expect(symlinkDirectory.relativize(symlinkPath)).toBe ''
        expect(symlinkDirectory.relativize(realFilePath)).toBe 'a'

      it "returns the full path if the directory's path is not a prefix of the path", ->
        expect(directory.relativize('/not/relative')).toBe '/not/relative'

    describe "on #win32", ->
      it "returns a relative path based on the directory's path", ->
        absolutePath = directory.getPath()
        expect(directory.relativize(absolutePath)).toBe ''
        expect(directory.relativize(path.join(absolutePath, "b"))).toBe "b"
        expect(directory.relativize(path.join(absolutePath, "b/file.coffee"))).toBe "b\\file.coffee"
        expect(directory.relativize(path.join(absolutePath, "file.coffee"))).toBe "file.coffee"

      it "returns the full path if the directory's path is not a prefix of the path", ->
        expect(directory.relativize('/not/relative')).toBe "\\not\\relative"

  describe ".contains(path)", ->
    it "returns true if the path is a child of the directory's path", ->
      absolutePath = directory.getPath()
      expect(directory.contains(path.join(absolutePath, "b"))).toBe true
      expect(directory.contains(path.join(absolutePath, "b", "file.coffee"))).toBe true
      expect(directory.contains(path.join(absolutePath, "file.coffee"))).toBe true

    it "returns false if the directory's path is not a prefix of the path", ->
      expect(directory.contains('/not/relative')).toBe false

    describe "on #darwin or #linux", ->
      it "returns true if the path is a child of the directory's symlinked source path", ->
        symlinkPath = path.join(__dirname, 'fixtures', 'symlink-to-dir')
        symlinkDirectory = new Directory(symlinkPath)
        realFilePath = require.resolve('./fixtures/dir/a')
        expect(symlinkDirectory.contains(realFilePath)).toBe true
