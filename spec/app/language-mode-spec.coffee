Project = require 'project'
Buffer = require 'text-buffer'
EditSession = require 'edit-session'

describe "LanguageMode", ->
  [editSession, buffer, languageMode] = []

  afterEach ->
    editSession.destroy()

  describe "javascript", ->
    beforeEach ->
      atom.activatePackage('javascript-tmbundle', sync: true)
      editSession = project.open('sample.js', autoIndent: false)
      {buffer, languageMode} = editSession

    describe ".minIndentLevelForRowRange(startRow, endRow)", ->
      it "returns the minimum indent level for the given row range", ->
        expect(languageMode.minIndentLevelForRowRange(4, 7)).toBe 2
        expect(languageMode.minIndentLevelForRowRange(5, 7)).toBe 2
        expect(languageMode.minIndentLevelForRowRange(5, 6)).toBe 3
        expect(languageMode.minIndentLevelForRowRange(9, 11)).toBe 1
        expect(languageMode.minIndentLevelForRowRange(10, 10)).toBe 0

    describe ".toggleLineCommentsForBufferRows(start, end)", ->
      it "comments/uncomments lines in the given range", ->
        languageMode.toggleLineCommentsForBufferRows(4, 7)
        expect(buffer.lineForRow(4)).toBe "    // while(items.length > 0) {"
        expect(buffer.lineForRow(5)).toBe "    //   current = items.shift();"
        expect(buffer.lineForRow(6)).toBe "    //   current < pivot ? left.push(current) : right.push(current);"
        expect(buffer.lineForRow(7)).toBe "    // }"

        languageMode.toggleLineCommentsForBufferRows(4, 5)
        expect(buffer.lineForRow(4)).toBe "    while(items.length > 0) {"
        expect(buffer.lineForRow(5)).toBe "      current = items.shift();"
        expect(buffer.lineForRow(6)).toBe "    //   current < pivot ? left.push(current) : right.push(current);"
        expect(buffer.lineForRow(7)).toBe "    // }"

    describe "fold suggestion", ->
      describe ".doesBufferRowStartFold(bufferRow)", ->
        it "returns true only when the buffer row starts a foldable region", ->
          expect(languageMode.doesBufferRowStartFold(0)).toBeTruthy()
          expect(languageMode.doesBufferRowStartFold(1)).toBeTruthy()
          expect(languageMode.doesBufferRowStartFold(2)).toBeFalsy()
          expect(languageMode.doesBufferRowStartFold(3)).toBeFalsy()

      describe ".rowRangeForCodeFoldAtBufferRow(bufferRow)", ->
        it "returns the start/end rows of the foldable region starting at the given row", ->
          expect(languageMode.rowRangeForCodeFoldAtBufferRow(0)).toEqual [0, 12]
          expect(languageMode.rowRangeForCodeFoldAtBufferRow(1)).toEqual [1, 9]
          expect(languageMode.rowRangeForCodeFoldAtBufferRow(2)).toBeNull()
          expect(languageMode.rowRangeForCodeFoldAtBufferRow(4)).toEqual [4, 7]

    describe "suggestedIndentForBufferRow", ->
      it "returns the suggested indentation based on auto-indent/outdent rules", ->
        expect(languageMode.suggestedIndentForBufferRow(0)).toBe 0
        expect(languageMode.suggestedIndentForBufferRow(1)).toBe 1
        expect(languageMode.suggestedIndentForBufferRow(2)).toBe 2
        expect(languageMode.suggestedIndentForBufferRow(9)).toBe 1

  describe "coffeescript", ->
    beforeEach ->
      atom.activatePackage('coffee-script-tmbundle', sync: true)
      editSession = project.open('coffee.coffee', autoIndent: false)
      {buffer, languageMode} = editSession

    describe ".toggleLineCommentsForBufferRows(start, end)", ->
      it "comments/uncomments lines in the given range", ->
        languageMode.toggleLineCommentsForBufferRows(4, 6)
        expect(buffer.lineForRow(4)).toBe "    # pivot = items.shift()"
        expect(buffer.lineForRow(5)).toBe "    # left = []"
        expect(buffer.lineForRow(6)).toBe "    # right = []"

        languageMode.toggleLineCommentsForBufferRows(4, 5)
        expect(buffer.lineForRow(4)).toBe "    pivot = items.shift()"
        expect(buffer.lineForRow(5)).toBe "    left = []"
        expect(buffer.lineForRow(6)).toBe "    # right = []"

      it "comments/uncomments lines when empty line", ->
        languageMode.toggleLineCommentsForBufferRows(4, 7)
        expect(buffer.lineForRow(4)).toBe "    # pivot = items.shift()"
        expect(buffer.lineForRow(5)).toBe "    # left = []"
        expect(buffer.lineForRow(6)).toBe "    # right = []"
        expect(buffer.lineForRow(7)).toBe "    # "

        languageMode.toggleLineCommentsForBufferRows(4, 5)
        expect(buffer.lineForRow(4)).toBe "    pivot = items.shift()"
        expect(buffer.lineForRow(5)).toBe "    left = []"
        expect(buffer.lineForRow(6)).toBe "    # right = []"
        expect(buffer.lineForRow(7)).toBe "    # "

    describe "fold suggestion", ->
      describe ".doesBufferRowStartFold(bufferRow)", ->
        it "returns true only when the buffer row starts a foldable region", ->
          expect(languageMode.doesBufferRowStartFold(0)).toBeTruthy()
          expect(languageMode.doesBufferRowStartFold(1)).toBeTruthy()
          expect(languageMode.doesBufferRowStartFold(2)).toBeFalsy()
          expect(languageMode.doesBufferRowStartFold(3)).toBeFalsy()
          expect(languageMode.doesBufferRowStartFold(19)).toBeTruthy()

      describe ".rowRangeForCodeFoldAtBufferRow(bufferRow)", ->
        it "returns the start/end rows of the foldable region starting at the given row", ->
          expect(languageMode.rowRangeForCodeFoldAtBufferRow(0)).toEqual [0, 20]
          expect(languageMode.rowRangeForCodeFoldAtBufferRow(1)).toEqual [1, 17]
          expect(languageMode.rowRangeForCodeFoldAtBufferRow(2)).toBeNull()
          expect(languageMode.rowRangeForCodeFoldAtBufferRow(19)).toEqual [19, 20]

  describe "css", ->
    beforeEach ->
      atom.activatePackage('css-tmbundle', sync: true)
      editSession = project.open('css.css', autoIndent: false)
      {buffer, languageMode} = editSession

    describe ".toggleLineCommentsForBufferRows(start, end)", ->
      it "comments/uncomments lines in the given range", ->
        languageMode.toggleLineCommentsForBufferRows(0, 1)
        expect(buffer.lineForRow(0)).toBe "/*body {"
        expect(buffer.lineForRow(1)).toBe "  font-size: 1234px;*/"
        expect(buffer.lineForRow(2)).toBe "  width: 110%;"
        expect(buffer.lineForRow(3)).toBe "  font-weight: bold !important;"

        languageMode.toggleLineCommentsForBufferRows(2, 2)
        expect(buffer.lineForRow(0)).toBe "/*body {"
        expect(buffer.lineForRow(1)).toBe "  font-size: 1234px;*/"
        expect(buffer.lineForRow(2)).toBe "/*  width: 110%;*/"
        expect(buffer.lineForRow(3)).toBe "  font-weight: bold !important;"

        languageMode.toggleLineCommentsForBufferRows(0, 1)
        expect(buffer.lineForRow(0)).toBe "body {"
        expect(buffer.lineForRow(1)).toBe "  font-size: 1234px;"
        expect(buffer.lineForRow(2)).toBe "/*  width: 110%;*/"
        expect(buffer.lineForRow(3)).toBe "  font-weight: bold !important;"

      it "uncomments lines with leading whitespace", ->
        buffer.change([[2, 0], [2, Infinity]], "  /*width: 110%;*/")
        languageMode.toggleLineCommentsForBufferRows(2, 2)
        expect(buffer.lineForRow(2)).toBe "  width: 110%;"

      it "uncomments lines with trailing whitespace", ->
        buffer.change([[2, 0], [2, Infinity]], "/*width: 110%;*/  ")
        languageMode.toggleLineCommentsForBufferRows(2, 2)
        expect(buffer.lineForRow(2)).toBe "width: 110%;  "

      it "uncomments lines with leading and trailing whitespace", ->
        buffer.change([[2, 0], [2, Infinity]], "   /*width: 110%;*/ ")
        languageMode.toggleLineCommentsForBufferRows(2, 2)
        expect(buffer.lineForRow(2)).toBe "   width: 110%; "

  describe "less", ->
    beforeEach ->
      atom.activatePackage('less-tmbundle', sync: true)
      atom.activatePackage('css-tmbundle', sync: true)
      editSession = project.open('sample.less', autoIndent: false)
      {buffer, languageMode} = editSession

    describe "when commenting lines", ->
      it "only uses the `commentEnd` pattern if it comes from the same grammar as the `commentStart`", ->
        languageMode.toggleLineCommentsForBufferRows(0, 0)
        expect(buffer.lineForRow(0)).toBe "// @color: #4D926F;"

  describe "folding", ->

    describe "with comments", ->
      beforeEach ->
        atom.activatePackage('javascript-tmbundle', sync: true)
        editSession = project.open('sample-with-comments.js', autoIndent: false)
        {buffer, languageMode} = editSession

      describe ".unfoldAll()", ->
        it "unfolds every folded line", ->
          initialScreenLineCount = editSession.getScreenLineCount()
          editSession.foldBufferRow(0)
          editSession.foldBufferRow(5)
          expect(editSession.getScreenLineCount()).toBeLessThan initialScreenLineCount
          editSession.unfoldAll()
          expect(editSession.getScreenLineCount()).toBe initialScreenLineCount

      describe ".foldAll()", ->
        it "folds every foldable line", ->
          editSession.foldAll()

          fold1 = editSession.lineForScreenRow(0).fold
          expect([fold1.getStartRow(), fold1.getEndRow()]).toEqual [0, 19]
          fold1.destroy()

          fold2 = editSession.lineForScreenRow(1).fold
          expect([fold2.getStartRow(), fold2.getEndRow()]).toEqual [1, 4]

          fold3 = editSession.lineForScreenRow(2).fold.destroy()

          fold4 = editSession.lineForScreenRow(3).fold
          expect([fold4.getStartRow(), fold4.getEndRow()]).toEqual [6, 8]





