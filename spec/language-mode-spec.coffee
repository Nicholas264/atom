describe "LanguageMode", ->
  [editor, buffer, languageMode] = []

  afterEach ->
    editor.destroy()

  describe "javascript", ->
    beforeEach ->
      atom.packages.activatePackage('language-javascript', sync: true)
      editor = atom.project.openSync('sample.js', autoIndent: false)
      {buffer, languageMode} = editor

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

        buffer.setText('\tvar i;')
        languageMode.toggleLineCommentsForBufferRows(0, 0)
        expect(buffer.lineForRow(0)).toBe "\t// var i;"

        buffer.setText('var i;')
        languageMode.toggleLineCommentsForBufferRows(0, 0)
        expect(buffer.lineForRow(0)).toBe "// var i;"

        buffer.setText(' var i;')
        languageMode.toggleLineCommentsForBufferRows(0, 0)
        expect(buffer.lineForRow(0)).toBe " // var i;"

    describe "fold suggestion", ->
      describe ".isFoldableAtBufferRow(bufferRow)", ->
        it "returns true only when the buffer row starts a foldable region", ->
          expect(languageMode.isFoldableAtBufferRow(0)).toBeTruthy()
          expect(languageMode.isFoldableAtBufferRow(1)).toBeTruthy()
          expect(languageMode.isFoldableAtBufferRow(2)).toBeFalsy()
          expect(languageMode.isFoldableAtBufferRow(3)).toBeFalsy()

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

    describe "rowRangeForParagraphAtBufferRow", ->
      describe "with code and comments", ->
        beforeEach ->
          buffer.setText '''
            var quicksort = function () {
              /* Single line comment block */
              var sort = function(items) {};

              /*
              A multiline
              comment is here
              */
              var sort = function(items) {};

              // A comment
              //
              // Multiple comment
              // lines
              var sort = function(items) {};
              // comment line after fn
            };
          '''

        it "will limit paragraph range to comments", ->
          range = languageMode.rowRangeForParagraphAtBufferRow(0)
          expect(range).toEqual [[0,0], [0,29]]

          range = languageMode.rowRangeForParagraphAtBufferRow(10)
          expect(range).toEqual [[10,0], [10,14]]
          range = languageMode.rowRangeForParagraphAtBufferRow(11)
          expect(range).toBeFalsy()
          range = languageMode.rowRangeForParagraphAtBufferRow(12)
          expect(range).toEqual [[12,0], [13,10]]

          range = languageMode.rowRangeForParagraphAtBufferRow(14)
          expect(range).toEqual [[14,0], [14,32]]

          range = languageMode.rowRangeForParagraphAtBufferRow(15)
          expect(range).toEqual [[15,0], [15,26]]

  describe "coffeescript", ->
    beforeEach ->
      atom.packages.activatePackage('language-coffee-script', sync: true)
      editor = atom.project.openSync('coffee.coffee', autoIndent: false)
      {buffer, languageMode} = editor

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
      describe ".isFoldableAtBufferRow(bufferRow)", ->
        it "returns true only when the buffer row starts a foldable region", ->
          expect(languageMode.isFoldableAtBufferRow(0)).toBeTruthy()
          expect(languageMode.isFoldableAtBufferRow(1)).toBeTruthy()
          expect(languageMode.isFoldableAtBufferRow(2)).toBeFalsy()
          expect(languageMode.isFoldableAtBufferRow(3)).toBeFalsy()
          expect(languageMode.isFoldableAtBufferRow(19)).toBeTruthy()

      describe ".rowRangeForCodeFoldAtBufferRow(bufferRow)", ->
        it "returns the start/end rows of the foldable region starting at the given row", ->
          expect(languageMode.rowRangeForCodeFoldAtBufferRow(0)).toEqual [0, 20]
          expect(languageMode.rowRangeForCodeFoldAtBufferRow(1)).toEqual [1, 17]
          expect(languageMode.rowRangeForCodeFoldAtBufferRow(2)).toBeNull()
          expect(languageMode.rowRangeForCodeFoldAtBufferRow(19)).toEqual [19, 20]

  describe "css", ->
    beforeEach ->
      atom.packages.activatePackage('language-css', sync: true)
      editor = atom.project.openSync('css.css', autoIndent: false)
      {buffer, languageMode} = editor

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
      atom.packages.activatePackage('language-less', sync: true)
      atom.packages.activatePackage('language-css', sync: true)
      editor = atom.project.openSync('sample.less', autoIndent: false)
      {buffer, languageMode} = editor

    describe "when commenting lines", ->
      it "only uses the `commentEnd` pattern if it comes from the same grammar as the `commentStart`", ->
        languageMode.toggleLineCommentsForBufferRows(0, 0)
        expect(buffer.lineForRow(0)).toBe "// @color: #4D926F;"

  describe "folding", ->
    beforeEach ->
      atom.packages.activatePackage('language-javascript', sync: true)
      editor = atom.project.openSync('sample.js', autoIndent: false)
      {buffer, languageMode} = editor

    it "maintains cursor buffer position when a folding/unfolding", ->
      editor.setCursorBufferPosition([5,5])
      languageMode.foldAll()
      expect(editor.getCursorBufferPosition()).toEqual([5,5])

    describe ".unfoldAll()", ->
      it "unfolds every folded line", ->
        initialScreenLineCount = editor.getScreenLineCount()
        languageMode.foldBufferRow(0)
        languageMode.foldBufferRow(1)
        expect(editor.getScreenLineCount()).toBeLessThan initialScreenLineCount
        languageMode.unfoldAll()
        expect(editor.getScreenLineCount()).toBe initialScreenLineCount

    describe ".foldAll()", ->
      it "folds every foldable line", ->
        languageMode.foldAll()

        fold1 = editor.lineForScreenRow(0).fold
        expect([fold1.getStartRow(), fold1.getEndRow()]).toEqual [0, 12]
        fold1.destroy()

        fold2 = editor.lineForScreenRow(1).fold
        expect([fold2.getStartRow(), fold2.getEndRow()]).toEqual [1, 9]
        fold2.destroy()

        fold3 = editor.lineForScreenRow(4).fold
        expect([fold3.getStartRow(), fold3.getEndRow()]).toEqual [4, 7]

    describe ".foldBufferRow(bufferRow)", ->
      describe "when bufferRow can be folded", ->
        it "creates a fold based on the syntactic region starting at the given row", ->
          languageMode.foldBufferRow(1)
          fold = editor.lineForScreenRow(1).fold
          expect(fold.getStartRow()).toBe 1
          expect(fold.getEndRow()).toBe 9

      describe "when bufferRow can't be folded", ->
        it "searches upward for the first row that begins a syntatic region containing the given buffer row (and folds it)", ->
          languageMode.foldBufferRow(8)
          fold = editor.lineForScreenRow(1).fold
          expect(fold.getStartRow()).toBe 1
          expect(fold.getEndRow()).toBe 9

      describe "when the bufferRow is already folded", ->
        it "searches upward for the first row that begins a syntatic region containing the folded row (and folds it)", ->
          languageMode.foldBufferRow(2)
          expect(editor.lineForScreenRow(1).fold).toBeDefined()
          expect(editor.lineForScreenRow(0).fold).not.toBeDefined()

          languageMode.foldBufferRow(1)
          expect(editor.lineForScreenRow(0).fold).toBeDefined()

      describe "when the bufferRow is in a multi-line comment", ->
        it "searches upward and downward for surrounding comment lines and folds them as a single fold", ->
          buffer.insert([1,0], "  //this is a comment\n  // and\n  //more docs\n\n//second comment")
          languageMode.foldBufferRow(1)
          fold = editor.lineForScreenRow(1).fold
          expect(fold.getStartRow()).toBe 1
          expect(fold.getEndRow()).toBe 3

      describe "when the bufferRow is a single-line comment", ->
        it "searches upward for the first row that begins a syntatic region containing the folded row (and folds it)", ->
          buffer.insert([1,0], "  //this is a single line comment\n")
          languageMode.foldBufferRow(1)
          fold = editor.lineForScreenRow(0).fold
          expect(fold.getStartRow()).toBe 0
          expect(fold.getEndRow()).toBe 13

    describe ".unfoldBufferRow(bufferRow)", ->
      describe "when bufferRow can be unfolded", ->
        it "destroys a fold based on the syntactic region starting at the given row", ->
          languageMode.foldBufferRow(1)
          expect(editor.lineForScreenRow(1).fold).toBeDefined()

          languageMode.unfoldBufferRow(1)
          expect(editor.lineForScreenRow(1).fold).toBeUndefined()

      describe "when bufferRow can't be unfolded", ->
        it "does not throw an error", ->
          expect(editor.lineForScreenRow(1).fold).toBeUndefined()
          languageMode.unfoldBufferRow(1)
          expect(editor.lineForScreenRow(1).fold).toBeUndefined()

    describe ".isFoldableAtBufferRow(bufferRow)", ->
      it "returns true if the line starts a foldable row range", ->
        expect(languageMode.isFoldableAtBufferRow(0)).toBe true
        expect(languageMode.isFoldableAtBufferRow(1)).toBe true
        expect(languageMode.isFoldableAtBufferRow(2)).toBe false
        expect(languageMode.isFoldableAtBufferRow(3)).toBe false
        expect(languageMode.isFoldableAtBufferRow(4)).toBe true

  describe "folding with comments", ->
    beforeEach ->
      atom.packages.activatePackage('language-javascript', sync: true)
      editor = atom.project.openSync('sample-with-comments.js', autoIndent: false)
      {buffer, languageMode} = editor

    describe ".unfoldAll()", ->
      it "unfolds every folded line", ->
        initialScreenLineCount = editor.getScreenLineCount()
        languageMode.foldBufferRow(0)
        languageMode.foldBufferRow(5)
        expect(editor.getScreenLineCount()).toBeLessThan initialScreenLineCount
        languageMode.unfoldAll()
        expect(editor.getScreenLineCount()).toBe initialScreenLineCount

    describe ".foldAll()", ->
      it "folds every foldable line", ->
        languageMode.foldAll()

        fold1 = editor.lineForScreenRow(0).fold
        expect([fold1.getStartRow(), fold1.getEndRow()]).toEqual [0, 19]
        fold1.destroy()

        fold2 = editor.lineForScreenRow(1).fold
        expect([fold2.getStartRow(), fold2.getEndRow()]).toEqual [1, 4]

        fold3 = editor.lineForScreenRow(2).fold.destroy()

        fold4 = editor.lineForScreenRow(3).fold
        expect([fold4.getStartRow(), fold4.getEndRow()]).toEqual [6, 8]

    describe ".foldAllAtIndentLevel()", ->
      it "folds every foldable range at a given indentLevel", ->
        languageMode.foldAllAtIndentLevel(2)

        fold1 = editor.lineForScreenRow(6).fold
        expect([fold1.getStartRow(), fold1.getEndRow()]).toEqual [6, 8]
        fold1.destroy()

        fold2 = editor.lineForScreenRow(11).fold
        expect([fold2.getStartRow(), fold2.getEndRow()]).toEqual [11, 14]
        fold2.destroy()

      it "does not fold anything but the indentLevel", ->
        languageMode.foldAllAtIndentLevel(0)

        fold1 = editor.lineForScreenRow(0).fold
        expect([fold1.getStartRow(), fold1.getEndRow()]).toEqual [0, 19]
        fold1.destroy()

        fold2 = editor.lineForScreenRow(5).fold
        expect(fold2).toBeFalsy()

    describe ".isFoldableAtBufferRow(bufferRow)", ->
      it "returns true if the line starts a multi-line comment", ->
        expect(languageMode.isFoldableAtBufferRow(1)).toBe true
        expect(languageMode.isFoldableAtBufferRow(6)).toBe true
        expect(languageMode.isFoldableAtBufferRow(17)).toBe false

  describe "css", ->
    beforeEach ->
      atom.packages.activatePackage('language-source', sync: true)
      atom.packages.activatePackage('language-css', sync: true)
      editor = atom.project.openSync('css.css', autoIndent: true)

    describe "suggestedIndentForBufferRow", ->
      it "does not return negative values (regression)", ->
        editor.setText('.test {\npadding: 0;\n}')
        expect(editor.suggestedIndentForBufferRow(2)).toBe 0
