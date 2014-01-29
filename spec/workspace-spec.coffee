Workspace = require '../src/workspace'

describe "Workspace", ->
  workspace = null

  beforeEach ->
    atom.project.setPath(atom.project.resolve('dir'))
    workspace = new Workspace

  describe "::open(uri)", ->
    beforeEach ->
      spyOn(workspace.activePane, 'activate')

    describe "when called without a uri", ->
      it "adds and activates an empty editor on the active pane", ->
        editor = null
        waitsForPromise ->
          workspace.open().then (o) -> editor = o

        runs ->
          expect(editor.getPath()).toBeUndefined()
          expect(workspace.activePane.items).toEqual [editor]
          expect(workspace.activePaneItem).toBe editor
          expect(workspace.activePane.activate).toHaveBeenCalled()

    describe "when called with a uri", ->
      describe "when the active pane already has an editor for the given uri", ->
        it "activates the existing editor on the active pane", ->
          editor1 = workspace.openSync('a')
          editor2 = workspace.openSync('b')

          editor = null
          waitsForPromise ->
            workspace.open('a').then (o) -> editor = o

          runs ->
            expect(editor).toBe editor1
            expect(workspace.activePaneItem).toBe editor
            expect(workspace.activePane.activate).toHaveBeenCalled()

      describe "when the active pane does not have an editor for the given uri", ->
        it "adds and activates a new editor for the given path on the active pane", ->
          editor = null
          waitsForPromise ->
            workspace.open('a').then (o) -> editor = o

          runs ->
            expect(editor.getUri()).toBe 'a'
            expect(workspace.activePaneItem).toBe editor
            expect(workspace.activePane.items).toEqual [editor]
            expect(workspace.activePane.activate).toHaveBeenCalled()

  describe "::openSync(uri, options)", ->
    [activePane, initialItemCount] = []

    beforeEach ->
      activePane = workspace.activePane
      spyOn(activePane, 'activate')
      initialItemCount = activePane.items.length

    describe "when called without a uri", ->
      it "adds and activates an empty editor on the active pane", ->
        editor = workspace.openSync()
        expect(activePane.items.length).toBe initialItemCount + 1
        expect(activePane.activeItem).toBe editor
        expect(editor.getPath()).toBeUndefined()
        expect(activePane.activate).toHaveBeenCalled()

    describe "when called with a uri", ->
      describe "when the active pane already has an editor for the given uri", ->
        it "activates the existing editor on the active pane", ->
          editor1 = workspace.openSync('a')
          editor2 = workspace.openSync('b')
          expect(activePane.activeItem).toBe editor2
          expect(activePane.items.length).toBe 2

          editor = workspace.openSync(editor1.getPath())
          expect(editor).toBe editor1
          expect(activePane.activeItem).toBe editor
          expect(activePane.activate).toHaveBeenCalled()
          expect(activePane.items.length).toBe 2

      describe "when the active pane does not have an editor for the given uri", ->
        it "adds and activates a new editor for the given path on the active pane", ->
          editor = workspace.openSync('a')
          expect(activePane.items.length).toBe 1
          expect(activePane.activeItem).toBe editor
          expect(activePane.activate).toHaveBeenCalled()

    describe "when the 'activatePane' option is false", ->
      it "does not activate the active pane", ->
        workspace.openSync('b', activatePane: false)
        expect(activePane.activate).not.toHaveBeenCalled()

  describe "::openSingletonSync(uri, options)", ->
    describe "when an editor for the given uri is already open on the active pane", ->
      it "activates the existing editor", ->
        editor1 = workspace.openSync('a')
        editor2 = workspace.openSync('b')
        expect(workspace.activePaneItem).toBe editor2
        workspace.openSingletonSync('a')
        expect(workspace.activePaneItem).toBe editor1

    describe "when an editor for the given uri is already open on an inactive pane", ->
      it "activates the existing editor on the inactive pane, then activates that pane", ->
        editor1 = workspace.openSync('a')
        pane1 = workspace.activePane
        pane2 = workspace.activePane.splitRight()
        editor2 = workspace.openSync('b')
        expect(workspace.activePaneItem).toBe editor2
        workspace.openSingletonSync('a')
        expect(workspace.activePane).toBe pane1
        expect(workspace.activePaneItem).toBe editor1

    describe "when no editor for the given uri is open in any pane", ->
      it "opens an editor for the given uri in the active pane", ->
        editor1 = workspace.openSingletonSync('a')
        expect(workspace.activePaneItem).toBe editor1

      describe "when the 'split' option is 'left'", ->
        it "opens the editor in the leftmost pane of the current pane axis", ->
          pane1 = workspace.activePane
          pane2 = pane1.splitRight()
          expect(workspace.activePane).toBe pane2
          editor1 = workspace.openSingletonSync('a', split: 'left')
          expect(workspace.activePane).toBe pane1
          expect(pane1.items).toEqual [editor1]
          expect(pane2.items).toEqual []

      describe "when the 'split' option is 'right'", ->
        describe "when the active pane is in a horizontal pane axis", ->
          it "activates the editor on the rightmost pane of the current pane axis", ->
            pane1 = workspace.activePane
            pane2 = pane1.splitRight()
            pane1.activate()
            editor1 = workspace.openSingletonSync('a', split: 'right')
            expect(workspace.activePane).toBe pane2
            expect(pane2.items).toEqual [editor1]
            expect(pane1.items).toEqual []

        describe "when the active pane is not in a horizontal pane axis", ->
          it "splits the current pane to the right, then activates the editor on the right pane", ->
            pane1 = workspace.activePane
            editor1 = workspace.openSingletonSync('a', split: 'right')
            pane2 = workspace.activePane
            expect(workspace.paneContainer.root.children).toEqual [pane1, pane2]
            expect(pane2.items).toEqual [editor1]
            expect(pane1.items).toEqual []

  describe "::reopenItemSync()", ->
    it "opens the uri associated with the last closed pane that isn't currently open", ->
      pane = workspace.activePane
      workspace.openSync('a')
      workspace.openSync('b')
      workspace.openSync('file1')
      workspace.openSync()

      # does not reopen items with no uri
      expect(workspace.activePaneItem.getUri()).toBeUndefined()
      pane.destroyActiveItem()
      workspace.reopenItemSync()
      expect(workspace.activePaneItem.getUri()).not.toBeUndefined()

      # destroy all items
      expect(workspace.activePaneItem.getUri()).toBe 'file1'
      pane.destroyActiveItem()
      expect(workspace.activePaneItem.getUri()).toBe 'b'
      pane.destroyActiveItem()
      expect(workspace.activePaneItem.getUri()).toBe 'a'
      pane.destroyActiveItem()

      # reopens items with uris
      expect(workspace.activePaneItem).toBeUndefined()
      workspace.reopenItemSync()
      expect(workspace.activePaneItem.getUri()).toBe 'a'

      # does not reopen items that are already open
      workspace.openSync('b')
      expect(workspace.activePaneItem.getUri()).toBe 'b'
      workspace.reopenItemSync()
      expect(workspace.activePaneItem.getUri()).toBe 'file1'

  describe "::increase/decreaseFontSize()", ->
    it "increases/decreases the font size without going below 1", ->
      atom.config.set('editor.fontSize', 1)
      workspace.increaseFontSize()
      expect(atom.config.get('editor.fontSize')).toBe 2
      workspace.increaseFontSize()
      expect(atom.config.get('editor.fontSize')).toBe 3
      workspace.decreaseFontSize()
      expect(atom.config.get('editor.fontSize')).toBe 2
      workspace.decreaseFontSize()
      expect(atom.config.get('editor.fontSize')).toBe 1
      workspace.decreaseFontSize()
      expect(atom.config.get('editor.fontSize')).toBe 1
