_ = require 'underscore'
fsUtils = require 'fs-utils'
Subscriber = require 'subscriber'
EventEmitter = require 'event-emitter'
Task = require 'task'
GitUtils = require 'git-utils'

# Public: Represents the underlying git operations performed by Atom.
#
# This class shouldn't be instantiated directly but instead by accessing the
# global project instance and calling `getRepo()`.
#
# ## Example
#
# ```coffeescript
# git = global.project.getRepo()
# console.log git.getOriginUrl()
# ```
module.exports =
class Git
  _.extend @prototype, Subscriber
  _.extend @prototype, EventEmitter

  # Private: Creates a new `Git` instance.
  #
  # * path: The path to the git repository to open
  # * options:
  #    + refreshOnWindowFocus:
  #      A Boolean that identifies if the windows should refresh
  @open: (path, options) ->
    return null unless path
    try
      new Git(path, options)
    catch e
      null

  @exists: (path) ->
    if git = @open(path)
      git.destroy()
      true
    else
      false

  path: null
  statuses: null
  upstream: null
  statusTask: null

  # Private: Creates a new `Git` object.
  #
  # * path: The {String} representing the path to your git working directory
  # * options:
  #    + refreshOnWindowFocus: If `true`, {#refreshIndex} and {#refreshStatus}
  #      are called on focus
  constructor: (path, options={}) ->
    @repo = GitUtils.open(path)
    unless @repo?
      throw new Error("No Git repository found searching path: #{path}")

    @statuses = {}
    @upstream = {ahead: 0, behind: 0}

    refreshOnWindowFocus = options.refreshOnWindowFocus ? true
    if refreshOnWindowFocus
      $ = require 'jquery'
      @subscribe $(window), 'focus', =>
        @refreshIndex()
        @refreshStatus()

    project?.eachBuffer this, (buffer) =>
      bufferStatusHandler = =>
        path = buffer.getPath()
        @getPathStatus(path) if path
      @subscribe buffer, 'saved', bufferStatusHandler
      @subscribe buffer, 'reloaded', bufferStatusHandler

  # Private:
  destroy: ->
    if @statusTask?
      @statusTask.terminate()
      @statusTask = null

    if @repo?
      @repo.release()
      @repo = null

    @unsubscribe()

  # Private: Returns the corresponding {Repository}
  getRepo: ->
    unless @repo?
      throw new Error("Repository has been destroyed")
    @repo

  # Public: Reread the index to update any values that have changed since the
  # last time the index was read.
  refreshIndex: -> @getRepo().refreshIndex()

  # Public: Returns the path of the repository.
  getPath: ->
    @path ?= fsUtils.absolute(@getRepo().getPath())

  # Public: Returns the working directory of the repository.
  getWorkingDirectory: -> @getRepo().getWorkingDirectory()

  # Public: Returns the status of a single path in the repository.
  #
  # * path: A String defining a relative path
  #
  # Returns a {Number}, FIXME representing what?
  getPathStatus: (path) ->
    currentPathStatus = @statuses[path] ? 0
    pathStatus = @getRepo().getStatus(@relativize(path)) ? 0
    if pathStatus > 0
      @statuses[path] = pathStatus
    else
      delete @statuses[path]
    if currentPathStatus isnt pathStatus
      @trigger 'status-changed', path, pathStatus
    pathStatus

  # Public: Determines if the given path is ignored.
  isPathIgnored: (path) -> @getRepo().isIgnored(@relativize(path))

  # Public: Determine if the given status indicates modification.
  isStatusModified: (status) -> @getRepo().isStatusModified(status)

  # Public: Determine if the given path is modified.
  isPathModified: (path) -> @isStatusModified(@getPathStatus(path))

  # Public: Determine if the given status indicates a new path.
  isStatusNew: (status) -> @getRepo().isStatusNew(status)

  # Public: Determine if the given path is new.
  isPathNew: (path) -> @isStatusNew(@getPathStatus(path))

  # Public: Makes a path relative to the repository's working directory.
  relativize: (path) -> @getRepo().relativize(path)

  # Public: Retrieves a shortened version of the HEAD reference value.
  #
  # This removes the leading segments of `refs/heads`, `refs/tags`, or
  # `refs/remotes`.  It also shortens the SHA-1 of a detached `HEAD` to 7
  # characters.
  #
  # Returns a String.
  getShortHead: -> @getRepo().getShortHead()

  # Public: Restore the contents of a path in the working directory and index
  # to the version at `HEAD`.
  #
  # This is essentially the same as running:
  # ```
  # git reset HEAD -- <path>
  # git checkout HEAD -- <path>
  # ```
  #
  # path - The String path to checkout
  #
  # Returns a {Boolean} that's `true` if the method was successful.
  checkoutHead: (path) ->
    headCheckedOut = @getRepo().checkoutHead(@relativize(path))
    @getPathStatus(path) if headCheckedOut
    headCheckedOut

  # Public: Retrieves the number of lines added and removed to a path.
  #
  # This compares the working directory contents of the path to the `HEAD`
  # version.
  #
  # * path:
  #   The String path to check
  #
  # Returns an object with two keys, `added` and `deleted`. These will always
  # be greater than 0.
  getDiffStats: (path) -> @getRepo().getDiffStats(@relativize(path))

  # Public: Identifies if a path is a submodule.
  #
  # * path:
  #   The String path to check
  #
  # Returns a {Boolean}.
  isSubmodule: (path) -> @getRepo().isSubmodule(@relativize(path))

  # Public: Retrieves the status of a directory.
  #
  # * path:
  #   The String path to check
  #
  # Returns a Number representing the status.
  getDirectoryStatus: (directoryPath)  ->
    directoryPath = "#{directoryPath}/"
    directoryStatus = 0
    for path, status of @statuses
      directoryStatus |= status if path.indexOf(directoryPath) is 0
    directoryStatus

  # Public: Retrieves the line diffs comparing the `HEAD` version of the given
  # path and the given text.
  #
  # This is similar to the commit numbers reported by `git status` when a
  # remote tracking branch exists.
  #
  # * path:
  #   The String path (relative to the repository)
  # * text:
  #   The String to compare against the `HEAD` contents
  #
  # Returns an object with two keys, `ahead` and `behind`. These will always be
  # greater than zero.
  getLineDiffs: (path, text) -> @getRepo().getLineDiffs(@relativize(path), text)

  # Public: Returns the git configuration value specified by the key.
  getConfigValue: (key) -> @getRepo().getConfigValue(key)

  # Public: Returns the origin url of the repository.
  getOriginUrl: -> @getConfigValue('remote.origin.url')

  # Public: Returns the upstream branch for the current HEAD, or null if there
  # is no upstream branch for the current HEAD.
  #
  # Examples
  #
  #   getUpstreamBranch()
  #   # => "refs/remotes/origin/master"
  #
  # Returns a String.
  getUpstreamBranch: -> @getRepo().getUpstreamBranch()

  # Public: ?
  getReferenceTarget: (reference) -> @getRepo().getReferenceTarget(reference)

  # Public: ?
  getAheadBehindCount: (reference) -> @getRepo().getAheadBehindCount(reference)

  # Public: ?
  hasBranch: (branch) -> @getReferenceTarget("refs/heads/#{branch}")?

  # Private:
  refreshStatus: ->
    @statusTask = Task.once 'repository-status-handler', @getPath(), ({statuses, upstream}) =>
      statusesUnchanged = _.isEqual(statuses, @statuses) and _.isEqual(upstream, @upstream)
      @statuses = statuses
      @upstream = upstream
      @trigger 'statuses-changed' unless statusesUnchanged
