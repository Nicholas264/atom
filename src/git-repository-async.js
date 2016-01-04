'use babel'

import fs from 'fs-plus'
import Git from 'nodegit'
import path from 'path'
import {Emitter, CompositeDisposable, Disposable} from 'event-kit'

const modifiedStatusFlags = Git.Status.STATUS.WT_MODIFIED | Git.Status.STATUS.INDEX_MODIFIED | Git.Status.STATUS.WT_DELETED | Git.Status.STATUS.INDEX_DELETED | Git.Status.STATUS.WT_TYPECHANGE | Git.Status.STATUS.INDEX_TYPECHANGE
const newStatusFlags = Git.Status.STATUS.WT_NEW | Git.Status.STATUS.INDEX_NEW
const deletedStatusFlags = Git.Status.STATUS.WT_DELETED | Git.Status.STATUS.INDEX_DELETED
const indexStatusFlags = Git.Status.STATUS.INDEX_NEW | Git.Status.STATUS.INDEX_MODIFIED | Git.Status.STATUS.INDEX_DELETED | Git.Status.STATUS.INDEX_RENAMED | Git.Status.STATUS.INDEX_TYPECHANGE
const ignoredStatusFlags = 1 << 14 // TODO: compose this from libgit2 constants
const submoduleMode = 57344 // TODO: compose this from libgit2 constants

// Just using this for _.isEqual and _.object, we should impl our own here
import _ from 'underscore-plus'

export default class GitRepositoryAsync {
  static open (path, options = {}) {
    // QUESTION: Should this wrap Git.Repository and reject with a nicer message?
    return new GitRepositoryAsync(path, options)
  }

  static get Git () {
    return Git
  }

  static get DestroyedErrorName () {
    return 'GitRepositoryAsync.destroyed'
  }

  constructor (_path, options = {}) {
    this.repo = null
    this.emitter = new Emitter()
    this.subscriptions = new CompositeDisposable()
    this.pathStatusCache = {}
    this.repoPromise = Git.Repository.openExt(_path, 0, '')
    this.isCaseInsensitive = fs.isCaseInsensitive()
    this.upstreamByPath = {}

    this._refreshingCount = 0

    let {refreshOnWindowFocus = true} = options
    if (refreshOnWindowFocus) {
      const onWindowFocus = () => this.refreshStatus()
      window.addEventListener('focus', onWindowFocus)
      this.subscriptions.add(new Disposable(() => window.removeEventListener('focus', onWindowFocus)))
    }

    const {project, subscribeToBuffers} = options
    this.project = project
    if (this.project && subscribeToBuffers) {
      this.project.getBuffers().forEach(buffer => this.subscribeToBuffer(buffer))
      this.subscriptions.add(this.project.onDidAddBuffer(buffer => this.subscribeToBuffer(buffer)))
    }
  }

  // Public: Destroy this {GitRepositoryAsync} object.
  //
  // This destroys any tasks and subscriptions and releases the underlying
  // libgit2 repository handle. This method is idempotent.
  destroy () {
    if (this.emitter) {
      this.emitter.emit('did-destroy')
      this.emitter.dispose()
      this.emitter = null
    }
    if (this.subscriptions) {
      this.subscriptions.dispose()
      this.subscriptions = null
    }

    this.repoPromise = null
  }

  // Event subscription
  // ==================

  // Public: Invoke the given callback when this GitRepositoryAsync's destroy()
  // method is invoked.
  //
  // * `callback` {Function}
  //
  // Returns a {Disposable} on which `.dispose()` can be called to unsubscribe.
  onDidDestroy (callback) {
    return this.emitter.on('did-destroy', callback)
  }

  // Public: Invoke the given callback when a specific file's status has
  // changed. When a file is updated, reloaded, etc, and the status changes, this
  // will be fired.
  //
  // * `callback` {Function}
  //   * `event` {Object}
  //     * `path` {String} the old parameters the decoration used to have
  //     * `pathStatus` {Number} representing the status. This value can be passed to
  //       {::isStatusModified} or {::isStatusNew} to get more information.
  //
  // Returns a {Disposable} on which `.dispose()` can be called to unsubscribe.
  onDidChangeStatus (callback) {
    return this.emitter.on('did-change-status', callback)
  }

  // Public: Invoke the given callback when a multiple files' statuses have
  // changed. For example, on window focus, the status of all the paths in the
  // repo is checked. If any of them have changed, this will be fired. Call
  // {::getPathStatus(path)} to get the status for your path of choice.
  //
  // * `callback` {Function}
  //
  // Returns a {Disposable} on which `.dispose()` can be called to unsubscribe.
  onDidChangeStatuses (callback) {
    return this.emitter.on('did-change-statuses', callback)
  }

  // Repository details
  // ==================

  // Public: A {String} indicating the type of version control system used by
  // this repository.
  //
  // Returns `"git"`.
  getType () {
    return 'git'
  }

  // Public: Returns a {Promise} which resolves to the {String} path of the
  // repository.
  getPath () {
    return this.repoPromise.then(repo => repo.path().replace(/\/$/, ''))
  }

  // Public: Returns a {Promise} which resolves to the {String} working
  // directory path of the repository.
  getWorkingDirectory () {
    return this.repoPromise.then(repo => repo.workdir())
  }

  // Public: Returns a {Promise} that resolves to true if at the root, false if
  // in a subfolder of the repository.
  isProjectAtRoot () {
    if (!this.project) return Promise.resolve(false)

    if (!this.projectAtRoot) {
      this.projectAtRoot = this.repoPromise
        .then(repo => this.project.relativize(repo.workdir()))
        .then(relativePath => relativePath === '')
    }

    return this.projectAtRoot
  }

  // Public: Makes a path relative to the repository's working directory.
  //
  // * `path` The {String} path to relativize.
  //
  // Returns a {Promise} which resolves to the relative {String} path.
  relativizeToWorkingDirectory (_path) {
    return this.repoPromise
      .then(repo => this.relativize(_path, repo.workdir()))
  }

  // Public: Makes a path relative to the repository's working directory.
  //
  // * `path` The {String} path to relativize.
  // * `workingDirectory` The {String} working directory path.
  //
  // Returns the relative {String} path.
  relativize (_path, workingDirectory) {
    // Cargo-culted from git-utils. The original implementation also handles
    // this.openedWorkingDirectory, which is set by git-utils when the
    // repository is opened. Those branches of the if tree aren't included here
    // yet, but if we determine we still need that here it should be simple to
    // port.
    //
    // The original implementation also handled null workingDirectory as it
    // pulled it from a sync function that could return null. We require it
    // to be passed here.
    if (!_path || !workingDirectory) {
      return _path
    }

    // Depending on where the paths come from, they may have a '/private/'
    // prefix. Standardize by stripping that out.
    _path = _path.replace(/^\/private\//, '/')
    workingDirectory = workingDirectory.replace(/^\/private\//, '/')

    if (process.platform === 'win32') {
      _path = _path.replace(/\\/g, '/')
    } else {
      if (_path[0] !== '/') {
        return _path
      }
    }

    if (!/\/$/.test(workingDirectory)) {
      workingDirectory = `${workingDirectory}/`
    }

    const originalPath = _path
    if (this.isCaseInsensitive) {
      _path = _path.toLowerCase()
      workingDirectory = workingDirectory.toLowerCase()
    }

    if (_path.indexOf(workingDirectory) === 0) {
      return originalPath.substring(workingDirectory.length)
    } else if (_path === workingDirectory) {
      return ''
    }

    return _path
  }

  // Public: Returns a {Promise} which resolves to whether the given branch
  // exists.
  hasBranch (branch) {
    return this.repoPromise
      .then(repo => repo.getBranch(branch))
      .then(branch => branch != null)
      .catch(_ => false)
  }

  // Public: Retrieves a shortened version of the HEAD reference value.
  //
  // This removes the leading segments of `refs/heads`, `refs/tags`, or
  // `refs/remotes`.  It also shortens the SHA-1 of a detached `HEAD` to 7
  // characters.
  //
  // * `path` An optional {String} path in the repository to get this information
  //   for, only needed if the repository contains submodules.
  //
  // Returns a {Promise} which resolves to a {String}.
  getShortHead (_path) {
    return this.getRepo(_path)
      .then(repo => repo.getCurrentBranch())
      .then(branch => branch.shorthand())
  }

  // Public: Is the given path a submodule in the repository?
  //
  // * `path` The {String} path to check.
  //
  // Returns a {Promise} that resolves true if the given path is a submodule in
  // the repository.
  isSubmodule (_path) {
    return this.repoPromise
      .then(repo => repo.openIndex())
      .then(index => Promise.all([index, this.relativizeToWorkingDirectory(_path)]))
      .then(([index, relativePath]) => {
        // TODO: This'll probably be wrong if the submodule doesn't exist in the
        // index yet? Is that a thing?
        const entry = index.getByPath(relativePath)
        if (!entry) return false

        return entry.mode === submoduleMode
      })
  }

  // Public: Returns the number of commits behind the current branch is from the
  // its upstream remote branch.
  //
  // * `reference` The {String} branch reference name.
  // * `path`      The {String} path in the repository to get this information
  //               for, only needed if the repository contains submodules.
  //
  // Returns a {Promise} which resolves to an {Object} with the following keys:
  //   * `ahead`  The {Number} of commits ahead.
  //   * `behind` The {Number} of commits behind.
  getAheadBehindCount (reference, _path) {
    return this.getRepo(_path)
      .then(repo => Promise.all([repo, repo.getBranch(reference)]))
      .then(([repo, local]) => {
        const upstream = Git.Branch.upstream(local)
        return Promise.all([repo, local, upstream])
      })
      .then(([repo, local, upstream]) => {
        return Git.Graph.aheadBehind(repo, local.target(), upstream.target())
      })
      .catch(_ => ({ahead: 0, behind: 0}))
  }

  // Public: Get the cached ahead/behind commit counts for the current branch's
  // upstream branch.
  //
  // * `path` An optional {String} path in the repository to get this information
  //   for, only needed if the repository has submodules.
  //
  // Returns an {Object} with the following keys:
  //   * `ahead`  The {Number} of commits ahead.
  //   * `behind` The {Number} of commits behind.
  getCachedUpstreamAheadBehindCount (_path) {
    return this.upstreamByPath[_path || '.']
  }

  // Public: Returns the git configuration value specified by the key.
  //
  // * `path` An optional {String} path in the repository to get this information
  //   for, only needed if the repository has submodules.
  //
  // Returns a {Promise} which resolves to the {String} git configuration value
  // specified by the key.
  getConfigValue (key, _path) {
    return this.getRepo(_path)
      .then(repo => repo.configSnapshot())
      .then(config => config.getStringBuf(key))
      .catch(_ => null)
  }

  // Public: Get the URL for the 'origin' remote.
  //
  // * `path` (optional) {String} path in the repository to get this information
  //   for, only needed if the repository has submodules.
  //
  // Returns a {Promise} which resolves to the {String} origin url of the
  // repository.
  getOriginURL (_path) {
    return this.getConfigValue('remote.origin.url', _path)
  }

  // Public: Returns the upstream branch for the current HEAD, or null if there
  // is no upstream branch for the current HEAD.
  //
  // * `path` An optional {String} path in the repo to get this information for,
  //   only needed if the repository contains submodules.
  //
  // Returns a {Promise} which resolves to a {String} branch name such as
  // `refs/remotes/origin/master`.
  getUpstreamBranch (_path) {
    return this.getRepo(_path)
      .then(repo => repo.getCurrentBranch())
      .then(branch => Git.Branch.upstream(branch))
  }

  // Public: Gets all the local and remote references.
  //
  // * `path` An optional {String} path in the repository to get this information
  //   for, only needed if the repository has submodules.
  //
  // Returns a {Promise} which resolves to an {Object} with the following keys:
  //  * `heads`   An {Array} of head reference names.
  //  * `remotes` An {Array} of remote reference names.
  //  * `tags`    An {Array} of tag reference names.
  getReferences (_path) {
    return this.getRepo(_path)
      .then(repo => repo.getReferences(Git.Reference.TYPE.LISTALL))
      .then(refs => {
        const heads = []
        const remotes = []
        const tags = []
        for (const ref of refs) {
          if (ref.isTag()) {
            tags.push(ref.name())
          } else if (ref.isRemote()) {
            remotes.push(ref.name())
          } else if (ref.isBranch()) {
            heads.push(ref.name())
          }
        }
        return {heads, remotes, tags}
      })
  }

  // Public: Get the SHA for the given reference.
  //
  // * `reference` The {String} reference to get the target of.
  // * `path` An optional {String} path in the repo to get the reference target
  //   for. Only needed if the repository contains submodules.
  //
  // Returns a {Promise} which resolves to the current {String} SHA for the
  // given reference.
  getReferenceTarget (reference, _path) {
    return this.getRepo(_path)
      .then(repo => Git.Reference.nameToId(repo, reference))
      .then(oid => oid.tostrS())
  }

  // Reading Status
  // ==============

  // Public: Resolves true if the given path is modified.
  //
  // * `path` The {String} path to check.
  //
  // Returns a {Promise} which resolves to a {Boolean} that's true if the `path`
  // is modified.
  isPathModified (_path) {
    return this._getStatus([_path])
      .then(statuses => statuses.some(status => status.isModified()))
  }

  // Public: Resolves true if the given path is new.
  //
  // * `path` The {String} path to check.
  //
  // Returns a {Promise} which resolves to a {Boolean} that's true if the `path`
  // is new.
  isPathNew (_path) {
    return this._getStatus([_path])
      .then(statuses => statuses.some(status => status.isNew()))
  }

  // Public: Is the given path ignored?
  //
  // * `path` The {String} path to check.
  //
  // Returns a {Promise} which resolves to a {Boolean} that's true if the `path`
  // is ignored.
  isPathIgnored (_path) {
    return this.repoPromise
      .then(repo => {
        const relativePath = this.relativize(_path, repo.workdir())
        return Git.Ignore.pathIsIgnored(repo, relativePath)
      })
      .then(ignored => Boolean(ignored))
  }

  // Get the status of a directory in the repository's working directory.
  //
  // * `directoryPath` The {String} path to check.
  //
  // Returns a {Promise} resolving to a {Number} representing the status. This
  // value can be passed to {::isStatusModified} or {::isStatusNew} to get more
  // information.
  getDirectoryStatus (directoryPath) {
    return this.repoPromise
      .then(repo => {
        const relativePath = this.relativize(directoryPath, repo.workdir())
        return this._getStatus([relativePath])
      })
      .then(statuses => {
        return Promise.all(statuses.map(s => s.statusBit())).then(bits => {
          return bits
            .filter(b => b > 0)
            .reduce((status, bit) => status | bit, 0)
        })
      })
  }

  // Refresh the status bit for the given path.
  //
  // Note that if the status of the path has changed, this will emit a
  // 'did-change-status' event.
  //
  // * `path` The {String} path whose status should be refreshed.
  //
  // Returns a {Promise} which resolves to a {Number} which is the refreshed
  // status bit for the path.
  refreshStatusForPath (_path) {
    this._refreshingCount++

    let relativePath
    return this.repoPromise
      .then(repo => {
        relativePath = this.relativize(_path, repo.workdir())
        return this._getStatus([relativePath])
      })
      .then(statuses => {
        const cachedStatus = this.pathStatusCache[relativePath] || 0
        const status = statuses[0] ? statuses[0].statusBit() : Git.Status.STATUS.CURRENT
        if (status !== cachedStatus) {
          if (status === Git.Status.STATUS.CURRENT) {
            delete this.pathStatusCache[relativePath]
          } else {
            this.pathStatusCache[relativePath] = status
          }

          this.emitter.emit('did-change-status', {path: _path, pathStatus: status})
        }

        return status
      })
      .then(status => {
        this._refreshingCount--
        return status
      })
  }

  // Returns a Promise that resolves to the status bit of a given path if it has
  // one, otherwise 'current'.
  getPathStatus (_path) {
    return this.refreshStatusForPath(_path)
  }

  // Public: Get the cached status for the given path.
  //
  // * `path` A {String} path in the repository, relative or absolute.
  //
  // Returns a {Promise} which resolves to a status {Number} or null if the
  // path is not in the cache.
  getCachedPathStatus (_path) {
    return this.relativizeToWorkingDirectory(_path)
      .then(relativePath => this.pathStatusCache[relativePath])
  }

  // Public: Get the cached statuses for the repository.
  //
  // Returns an {Object} of {Number} statuses, keyed by {String} working
  // directory-relative file names.
  getCachedPathStatuses () {
    return this.pathStatusCache
  }

  // Public: Returns true if the given status indicates modification.
  //
  // * `statusBit` A {Number} representing the status.
  //
  // Returns a {Boolean} that's true if the `statusBit` indicates modification.
  isStatusModified (statusBit) {
    return (statusBit & modifiedStatusFlags) > 0
  }

  // Public: Returns true if the given status indicates a new path.
  //
  // * `statusBit` A {Number} representing the status.
  //
  // Returns a {Boolean} that's true if the `statusBit` indicates a new path.
  isStatusNew (statusBit) {
    return (statusBit & newStatusFlags) > 0
  }

  // Public: Returns true if the given status indicates the path is staged.
  //
  // * `statusBit` A {Number} representing the status.
  //
  // Returns a {Boolean} that's true if the `statusBit` indicates the path is
  // staged.
  isStatusStaged (statusBit) {
    return (statusBit & indexStatusFlags) > 0
  }

  // Public: Returns true if the given status indicates the path is ignored.
  //
  // * `statusBit` A {Number} representing the status.
  //
  // Returns a {Boolean} that's true if the `statusBit` indicates the path is
  // ignored.
  isStatusIgnored (statusBit) {
    return (statusBit & ignoredStatusFlags) > 0
  }

  // Public: Returns true if the given status indicates the path is deleted.
  //
  // * `statusBit` A {Number} representing the status.
  //
  // Returns a {Boolean} that's true if the `statusBit` indicates the path is
  // deleted.
  isStatusDeleted (statusBit) {
    return (statusBit & deletedStatusFlags) > 0
  }

  // Retrieving Diffs
  // ================
  // Public: Retrieves the number of lines added and removed to a path.
  //
  // This compares the working directory contents of the path to the `HEAD`
  // version.
  //
  // * `path` The {String} path to check.
  //
  // Returns a {Promise} which resolves to an {Object} with the following keys:
  //   * `added` The {Number} of added lines.
  //   * `deleted` The {Number} of deleted lines.
  getDiffStats (_path) {
    return this.repoPromise
      .then(repo => Promise.all([repo, repo.getHeadCommit()]))
      .then(([repo, headCommit]) => Promise.all([repo, headCommit.getTree()]))
      .then(([repo, tree]) => {
        const options = new Git.DiffOptions()
        options.pathspec = this.relativize(_path, repo.workdir())
        return Git.Diff.treeToWorkdir(repo, tree, options)
      })
      .then(diff => this._getDiffLines(diff))
      .then(lines => {
        const stats = {added: 0, deleted: 0}
        for (const line of lines) {
          const origin = line.origin()
          if (origin === Git.Diff.LINE.ADDITION) {
            stats.added++
          } else if (origin === Git.Diff.LINE.DELETION) {
            stats.deleted++
          }
        }
        return stats
      })
  }

  // Public: Retrieves the line diffs comparing the `HEAD` version of the given
  // path and the given text.
  //
  // * `path` The {String} path relative to the repository.
  // * `text` The {String} to compare against the `HEAD` contents
  //
  // Returns an {Array} of hunk {Object}s with the following keys:
  //   * `oldStart` The line {Number} of the old hunk.
  //   * `newStart` The line {Number} of the new hunk.
  //   * `oldLines` The {Number} of lines in the old hunk.
  //   * `newLines` The {Number} of lines in the new hunk
  getLineDiffs (_path, text) {
    let relativePath = null
    return this.repoPromise
      .then(repo => {
        relativePath = this.relativize(_path, repo.workdir())
        return repo.getHeadCommit()
      })
      .then(commit => commit.getEntry(relativePath))
      .then(entry => entry.getBlob())
      .then(blob => {
        const options = new Git.DiffOptions()
        options.contextLines = 0
        if (process.platform === 'win32') {
          // Ignore eol of line differences on windows so that files checked in
          // as LF don't report every line modified when the text contains CRLF
          // endings.
          options.flags = Git.Diff.OPTION.IGNORE_WHITESPACE_EOL
        }
        return this._diffBlobToBuffer(blob, text, options)
      })
  }

  // Checking Out
  // ============

  // Public: Restore the contents of a path in the working directory and index
  // to the version at `HEAD`.
  //
  // This is essentially the same as running:
  //
  // ```sh
  //   git reset HEAD -- <path>
  //   git checkout HEAD -- <path>
  // ```
  //
  // * `path` The {String} path to checkout.
  //
  // Returns a {Promise} that resolves or rejects depending on whether the
  // method was successful.
  checkoutHead (_path) {
    return this.repoPromise
      .then(repo => {
        const checkoutOptions = new Git.CheckoutOptions()
        checkoutOptions.paths = [this.relativize(_path, repo.workdir())]
        checkoutOptions.checkoutStrategy = Git.Checkout.STRATEGY.FORCE | Git.Checkout.STRATEGY.DISABLE_PATHSPEC_MATCH
        return Git.Checkout.head(repo, checkoutOptions)
      })
      .then(() => this.refreshStatusForPath(_path))
  }

  // Public: Checks out a branch in your repository.
  //
  // * `reference` The {String} reference to checkout.
  // * `create`    A {Boolean} value which, if true creates the new reference if
  //   it doesn't exist.
  //
  // Returns a {Promise} that resolves if the method was successful.
  checkoutReference (reference, create) {
    return this.repoPromise
      .then(repo => repo.checkoutBranch(reference))
      .catch(error => {
        if (create) {
          return this._createBranch(reference)
            .then(_ => this.checkoutReference(reference, false))
        } else {
          throw error
        }
      })
      .then(_ => null)
  }

  // Private
  // =======

  checkoutHeadForEditor (editor) {
    return new Promise((resolve, reject) => {
      const filePath = editor.getPath()
      if (filePath) {
        if (editor.buffer.isModified()) {
          editor.buffer.reload()
        }
        resolve(filePath)
      } else {
        reject()
      }
    }).then(filePath => this.checkoutHead(filePath))
  }

  // Create a new branch with the given name.
  //
  // * `name` The {String} name of the new branch.
  //
  // Returns a {Promise} which resolves to a {NodeGit.Ref} reference to the
  // created branch.
  _createBranch (name) {
    return this.repoPromise
      .then(repo => Promise.all([repo, repo.getHeadCommit()]))
      .then(([repo, commit]) => repo.createBranch(name, commit))
  }

  // Get all the hunks in the diff.
  //
  // * `diff` The {NodeGit.Diff} whose hunks should be retrieved.
  //
  // Returns a {Promise} which resolves to an {Array} of {NodeGit.Hunk}.
  _getDiffHunks (diff) {
    return diff.patches()
      .then(patches => Promise.all(patches.map(p => p.hunks()))) // patches :: Array<Patch>
      .then(hunks => _.flatten(hunks)) // hunks :: Array<Array<Hunk>>
  }

  // Get all the lines contained in the diff.
  //
  // * `diff` The {NodeGit.Diff} use lines should be retrieved.
  //
  // Returns a {Promise} which resolves to an {Array} of {NodeGit.Line}.
  _getDiffLines (diff) {
    return this._getDiffHunks(diff)
      .then(hunks => Promise.all(hunks.map(h => h.lines())))
      .then(lines => _.flatten(lines)) // lines :: Array<Array<Line>>
  }

  // Diff the given blob and buffer with the provided options.
  //
  // * `blob` The {NodeGit.Blob}
  // * `buffer` The {String} buffer.
  // * `options` The {NodeGit.DiffOptions}
  //
  // Returns a {Promise} which resolves to an {Array} of {Object}s which have
  // the following keys:
  //   * `oldStart` The {Number} of the old starting line.
  //   * `newStart` The {Number} of the new starting line.
  //   * `oldLines` The {Number} of old lines.
  //   * `newLines` The {Number} of new lines.
  _diffBlobToBuffer (blob, buffer, options) {
    const hunks = []
    const hunkCallback = (delta, hunk, payload) => {
      hunks.push({
        oldStart: hunk.oldStart(),
        newStart: hunk.newStart(),
        oldLines: hunk.oldLines(),
        newLines: hunk.newLines()
      })
    }

    return Git.Diff.blobToBuffer(blob, null, buffer, null, options, null, null, hunkCallback, null)
      .then(_ => hunks)
  }

  // Get the current branch and update this.branch.
  //
  // Returns a {Promise} which resolves to the {String} branch name.
  _refreshBranch () {
    return this.repoPromise
      .then(repo => repo.getCurrentBranch())
      .then(ref => ref.name())
      .then(branchName => this.branch = branchName)
  }

  // Refresh the cached ahead/behind count with the given branch.
  //
  // * `branchName` The {String} name of the branch whose ahead/behind should be
  //                used for the refresh.
  //
  // Returns a {Promise} which will resolve to {null}.
  _refreshAheadBehindCount (branchName) {
    return this.getAheadBehindCount(branchName)
      .then(counts => this.upstreamByPath['.'] = counts)
  }

  // Refresh the cached status.
  //
  // Returns a {Promise} which will resolve to {null}.
  _refreshStatus () {
    this._refreshingCount++

    let projectPathsPromises = Promise.resolve([])
    if (this.project) {
      projectPathsPromises = this.project.getPaths()
        .map(p => this.relativizeToWorkingDirectory(p))
    }

    Promise.all(projectPathsPromises)
      .then(paths => paths.filter(p => p.length > 0))
      .then(projectPaths => {
        if (this._isDestroyed()) return []

        return this._getStatus(projectPaths.length > 0 ? projectPaths : null)
      })
      .then(statuses => {
        const statusPairs = statuses.map(status => [status.path(), status.statusBit()])
        return Promise.all(statusPairs)
          .then(statusesByPath => _.object(statusesByPath))
      })
      .then(newPathStatusCache => {
        if (!_.isEqual(this.pathStatusCache, newPathStatusCache) && this.emitter != null) {
          this.emitter.emit('did-change-statuses')
        }
        this.pathStatusCache = newPathStatusCache
        return newPathStatusCache
      })
      .then(_ => this._refreshingCount--)
  }

  // Refreshes the git status.
  //
  // Returns a {Promise} which will resolve to {null} when refresh is complete.
  refreshStatus () {
    // TODO add submodule tracking

    const status = this._refreshStatus()
    const branch = this._refreshBranch()
    const aheadBehind = branch.then(branchName => this._refreshAheadBehindCount(branchName))

    return Promise.all([status, branch, aheadBehind]).then(_ => null)
  }

  // Get the NodeGit repository for the given path.
  //
  // * `path` The optional {String} path within the repository. This is only
  //          needed if you want to get the repository for that path if it is a
  //          submodule.
  //
  // Returns a {Promise} which resolves to the {NodeGit.Repository}.
  getRepo (_path) {
    if (this._isDestroyed()) {
      const error = new Error('Repository has been destroyed')
      error.name = GitRepositoryAsync.DestroyedErrorName
      return Promise.reject(error)
    }

    if (!_path) return this.repoPromise

    return this.isSubmodule(_path)
      .then(isSubmodule => {
        if (isSubmodule) {
          return Git.Repository.open(_path)
        } else {
          return this.repoPromise
        }
      })
  }

  // Section: Private
  // ================

  // Is the repository currently refreshing its status?
  //
  // Returns a {Boolean}.
  _isRefreshing () {
    return this._refreshingCount === 0
  }

  // Has the repository been destroyed?
  //
  // Returns a {Boolean}.
  _isDestroyed () {
    return this.repoPromise == null
  }

  // Subscribe to events on the given buffer.
  subscribeToBuffer (buffer) {
    const bufferSubscriptions = new CompositeDisposable()

    const refreshStatusForBuffer = () => {
      const _path = buffer.getPath()
      if (_path) {
        this.refreshStatusForPath(_path)
      }
    }

    bufferSubscriptions.add(
      buffer.onDidSave(refreshStatusForBuffer),
      buffer.onDidReload(refreshStatusForBuffer),
      buffer.onDidChangePath(refreshStatusForBuffer),
      buffer.onDidDestroy(() => {
        bufferSubscriptions.dispose()
        this.subscriptions.remove(bufferSubscriptions)
      })
    )

    this.subscriptions.add(bufferSubscriptions)
  }

  // Get the status for the given paths.
  //
  // * `paths` The {String} paths whose status is wanted. If undefined, get the
  //           status for the whole repository.
  //
  // Returns a {Promise} which resolves to an {Array} of {NodeGit.StatusFile}
  // statuses for the paths.
  _getStatus (paths) {
    return this.repoPromise
      .then(repo => {
        const opts = {
          flags: Git.Status.OPT.INCLUDE_UNTRACKED | Git.Status.OPT.RECURSE_UNTRACKED_DIRS | Git.Status.OPT.DISABLE_PATHSPEC_MATCH
        }

        if (paths) {
          opts.pathspec = paths
        }

        return repo.getStatus(opts)
      })
  }
}
