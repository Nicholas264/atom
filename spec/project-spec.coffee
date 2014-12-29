temp = require 'temp'
fstream = require 'fstream'
Project = require '../src/project'
_ = require 'underscore-plus'
fs = require 'fs-plus'
path = require 'path'
BufferedProcess = require '../src/buffered-process'

describe "Project", ->
  beforeEach ->
    atom.project.setPaths([atom.project.resolve('dir')])

  describe "serialization", ->
    deserializedProject = null

    afterEach ->
      deserializedProject?.destroy()

    it "does not include unretained buffers in the serialized state", ->
      waitsForPromise ->
        atom.project.bufferForPath('a')

      runs ->
        expect(atom.project.getBuffers().length).toBe 1
        deserializedProject = atom.project.testSerialization()
        expect(deserializedProject.getBuffers().length).toBe 0

    it "listens for destroyed events on deserialized buffers and removes them when they are destroyed", ->
      waitsForPromise ->
        atom.project.open('a')

      runs ->
        expect(atom.project.getBuffers().length).toBe 1
        deserializedProject = atom.project.testSerialization()

        expect(deserializedProject.getBuffers().length).toBe 1
        deserializedProject.getBuffers()[0].destroy()
        expect(deserializedProject.getBuffers().length).toBe 0

  describe "when an editor is saved and the project has no path", ->
    it "sets the project's path to the saved file's parent directory", ->
      tempFile = temp.openSync().path
      atom.project.setPaths([])
      expect(atom.project.getPaths()[0]).toBeUndefined()
      editor = null

      waitsForPromise ->
        atom.project.open().then (o) -> editor = o

      runs ->
        editor.saveAs(tempFile)
        expect(atom.project.getPaths()[0]).toBe path.dirname(tempFile)

  describe ".open(path)", ->
    [absolutePath, newBufferHandler] = []

    beforeEach ->
      absolutePath = require.resolve('./fixtures/dir/a')
      newBufferHandler = jasmine.createSpy('newBufferHandler')
      atom.project.on 'buffer-created', newBufferHandler

    describe "when given an absolute path that isn't currently open", ->
      it "returns a new edit session for the given path and emits 'buffer-created'", ->
        editor = null
        waitsForPromise ->
          atom.project.open(absolutePath).then (o) -> editor = o

        runs ->
          expect(editor.buffer.getPath()).toBe absolutePath
          expect(newBufferHandler).toHaveBeenCalledWith editor.buffer

    describe "when given a relative path that isn't currently opened", ->
      it "returns a new edit session for the given path (relative to the project root) and emits 'buffer-created'", ->
        editor = null
        waitsForPromise ->
          atom.project.open(absolutePath).then (o) -> editor = o

        runs ->
          expect(editor.buffer.getPath()).toBe absolutePath
          expect(newBufferHandler).toHaveBeenCalledWith editor.buffer

    describe "when passed the path to a buffer that is currently opened", ->
      it "returns a new edit session containing currently opened buffer", ->
        editor = null

        waitsForPromise ->
          atom.project.open(absolutePath).then (o) -> editor = o

        runs ->
          newBufferHandler.reset()

        waitsForPromise ->
          atom.project.open(absolutePath).then ({buffer}) ->
            expect(buffer).toBe editor.buffer

        waitsForPromise ->
          atom.project.open('a').then ({buffer}) ->
            expect(buffer).toBe editor.buffer
            expect(newBufferHandler).not.toHaveBeenCalled()

    describe "when not passed a path", ->
      it "returns a new edit session and emits 'buffer-created'", ->
        editor = null
        waitsForPromise ->
          atom.project.open().then (o) -> editor = o

        runs ->
          expect(editor.buffer.getPath()).toBeUndefined()
          expect(newBufferHandler).toHaveBeenCalledWith(editor.buffer)

    it "returns number of read bytes as progress indicator", ->
      filePath = atom.project.resolve 'a'
      totalBytes = 0
      promise = atom.project.open(filePath)
      promise.progress (bytesRead) -> totalBytes = bytesRead

      waitsForPromise ->
        promise

      runs ->
        expect(totalBytes).toBe fs.statSync(filePath).size

  describe ".bufferForPath(path)", ->
    [buffer] = []
    beforeEach ->
      waitsForPromise ->
        atom.project.bufferForPath("a").then (o) ->
          buffer = o
          buffer.retain()

    afterEach ->
      buffer.release()

    describe "when opening a previously opened path", ->
      it "does not create a new buffer", ->
        waitsForPromise ->
          atom.project.bufferForPath("a").then (anotherBuffer) ->
            expect(anotherBuffer).toBe buffer

        waitsForPromise ->
          atom.project.bufferForPath("b").then (anotherBuffer) ->
            expect(anotherBuffer).not.toBe buffer

      it "creates a new buffer if the previous buffer was destroyed", ->
        buffer.release()

        waitsForPromise ->
          atom.project.bufferForPath("b").then (anotherBuffer) ->
            expect(anotherBuffer).not.toBe buffer

  describe ".resolve(uri)", ->
    describe "when passed an absolute or relative path", ->
      it "returns an absolute path based on the atom.project's root", ->
        absolutePath = require.resolve('./fixtures/dir/a')
        expect(atom.project.resolve('a')).toBe absolutePath
        expect(atom.project.resolve(absolutePath + '/../a')).toBe absolutePath
        expect(atom.project.resolve('a/../a')).toBe absolutePath
        expect(atom.project.resolve()).toBeUndefined()

    describe "when passed a uri with a scheme", ->
      it "does not modify uris that begin with a scheme", ->
        expect(atom.project.resolve('http://zombo.com')).toBe 'http://zombo.com'

    describe "when the project has no path", ->
      it "returns undefined for relative URIs", ->
        atom.project.setPaths([])
        expect(atom.project.resolve('test.txt')).toBeUndefined()
        expect(atom.project.resolve('http://github.com')).toBe 'http://github.com'
        absolutePath = fs.absolute(__dirname)
        expect(atom.project.resolve(absolutePath)).toBe absolutePath

  describe ".setPaths(path)", ->
    describe "when path is a file", ->
      it "sets its path to the files parent directory and updates the root directory", ->
        atom.project.setPaths([require.resolve('./fixtures/dir/a')])
        expect(atom.project.getPaths()[0]).toEqual path.dirname(require.resolve('./fixtures/dir/a'))
        expect(atom.project.getDirectories()[0].path).toEqual path.dirname(require.resolve('./fixtures/dir/a'))

    describe "when path is a directory", ->
      it "sets its path to the directory and updates the root directory", ->
        directory = fs.absolute(path.join(__dirname, 'fixtures', 'dir', 'a-dir'))
        atom.project.setPaths([directory])
        expect(atom.project.getPaths()[0]).toEqual directory
        expect(atom.project.getDirectories()[0].path).toEqual directory

    describe "when path is null", ->
      it "sets its path and root directory to null", ->
        atom.project.setPaths([])
        expect(atom.project.getPaths()[0]?).toBeFalsy()
        expect(atom.project.getDirectories()[0]?).toBeFalsy()

    it "normalizes the path to remove consecutive slashes, ., and .. segments", ->
      atom.project.setPaths(["#{require.resolve('./fixtures/dir/a')}#{path.sep}b#{path.sep}#{path.sep}.."])
      expect(atom.project.getPaths()[0]).toEqual path.dirname(require.resolve('./fixtures/dir/a'))
      expect(atom.project.getDirectories()[0].path).toEqual path.dirname(require.resolve('./fixtures/dir/a'))

  describe ".replace()", ->
    [filePath, commentFilePath, sampleContent, sampleCommentContent] = []

    beforeEach ->
      atom.project.setPaths([atom.project.resolve('../')])

      filePath = atom.project.resolve('sample.js')
      commentFilePath = atom.project.resolve('sample-with-comments.js')
      sampleContent = fs.readFileSync(filePath).toString()
      sampleCommentContent = fs.readFileSync(commentFilePath).toString()

    afterEach ->
      fs.writeFileSync(filePath, sampleContent)
      fs.writeFileSync(commentFilePath, sampleCommentContent)

    describe "when a file doesn't exist", ->
      it "calls back with an error", ->
        errors = []
        missingPath = path.resolve('/not-a-file.js')
        expect(fs.existsSync(missingPath)).toBeFalsy()

        waitsForPromise ->
          atom.project.replace /items/gi, 'items', [missingPath], (result, error) ->
            errors.push(error)

        runs ->
          expect(errors).toHaveLength 1
          expect(errors[0].path).toBe missingPath

    describe "when called with unopened files", ->
      it "replaces properly", ->
        results = []
        waitsForPromise ->
          atom.project.replace /items/gi, 'items', [filePath], (result) ->
            results.push(result)

        runs ->
          expect(results).toHaveLength 1
          expect(results[0].filePath).toBe filePath
          expect(results[0].replacements).toBe 6

    describe "when a buffer is already open", ->
      it "replaces properly and saves when not modified", ->
        editor = null
        results = []

        waitsForPromise ->
          atom.project.open('sample.js').then (o) -> editor = o

        runs ->
          expect(editor.isModified()).toBeFalsy()

        waitsForPromise ->
          atom.project.replace /items/gi, 'items', [filePath], (result) ->
            results.push(result)

        runs ->
          expect(results).toHaveLength 1
          expect(results[0].filePath).toBe filePath
          expect(results[0].replacements).toBe 6

          expect(editor.isModified()).toBeFalsy()

      it "does not replace when the path is not specified", ->
        editor = null
        results = []

        waitsForPromise ->
          atom.project.open('sample-with-comments.js').then (o) -> editor = o

        waitsForPromise ->
          atom.project.replace /items/gi, 'items', [commentFilePath], (result) ->
            results.push(result)

        runs ->
          expect(results).toHaveLength 1
          expect(results[0].filePath).toBe commentFilePath

      it "does NOT save when modified", ->
        editor = null
        results = []

        waitsForPromise ->
          atom.project.open('sample.js').then (o) -> editor = o

        runs ->
          editor.buffer.setTextInRange([[0,0],[0,0]], 'omg')
          expect(editor.isModified()).toBeTruthy()

        waitsForPromise ->
          atom.project.replace /items/gi, 'okthen', [filePath], (result) ->
            results.push(result)

        runs ->
          expect(results).toHaveLength 1
          expect(results[0].filePath).toBe filePath
          expect(results[0].replacements).toBe 6

          expect(editor.isModified()).toBeTruthy()

  describe ".eachBuffer(callback)", ->
    beforeEach ->
      atom.project.bufferForPathSync('a')

    it "invokes the callback for existing buffer", ->
      count = 0
      count = 0
      callbackBuffer = null
      callback = (buffer) ->
        callbackBuffer = buffer
        count++
      atom.project.eachBuffer(callback)
      expect(count).toBe 1
      expect(callbackBuffer).toBe atom.project.getBuffers()[0]

    it "invokes the callback for new buffers", ->
      count = 0
      callbackBuffer = null
      callback = (buffer) ->
        callbackBuffer = buffer
        count++

      atom.project.eachBuffer(callback)
      count = 0
      callbackBuffer = null
      atom.project.bufferForPathSync(require.resolve('./fixtures/sample.txt'))
      expect(count).toBe 1
      expect(callbackBuffer).toBe atom.project.getBuffers()[1]
