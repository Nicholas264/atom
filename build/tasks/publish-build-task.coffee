child_process = require 'child_process'
path = require 'path'

_ = require 'underscore-plus'
async = require 'async'
fs = require 'fs-plus'
GitHub = require 'github-releases'
request = require 'request'

grunt = null
maxReleases = 10
assets = [
  {assetName: 'atom-mac.zip', sourceName: 'Atom.app'}
  {assetName: 'atom-mac-symbols.zip', sourceName: 'Atom.breakpad.syms'}
]
commitSha = process.env.JANKY_SHA1
token = process.env.ATOM_ACCESS_TOKEN
defaultHeaders =
  Authorization: "token #{token}"
  'User-Agent': 'Atom'

module.exports = (gruntObject) ->
  grunt = gruntObject

  grunt.registerTask 'publish-build', 'Publish the built app', ->
    return unless process.platform is 'darwin'
    return if process.env.JANKY_SHA1 and process.env.JANKY_BRANCH isnt 'master'

    done = @async()
    buildDir = grunt.config.get('atom.buildDir')

    createBuildRelease (error, release) ->
      return done(error) if error?

      zipApps buildDir, assets, (error) ->
        return done(error) if error?
        uploadAssets release, buildDir, assets, (error) ->
          return done(error) if error?
          publishRelease release, (error) ->
            return done(error) if error?
            getAtomDraftRelease (error, release) ->
              return done(error) if error?
              assetNames = (asset.assetName for asset in assets)
              deleteExistingAssets release, assetNames, (error) ->
                return done(error) if error?
                uploadAssets(release, buildDir, assets, done)

logError = (message, error, details) ->
  grunt.log.error(message)
  grunt.log.error(error.message ? error) if error?
  grunt.log.error(details) if details

zipApps = (buildDir, assets, callback) ->
  zip = (directory, sourceName, assetName, callback) ->
    options = {cwd: directory, maxBuffer: Infinity}
    child_process.exec "zip -r --symlinks #{assetName} #{sourceName}", options, (error, stdout, stderr) ->
      if error?
        logError("Zipping #{sourceName} failed", error, stderr)
      callback(error)

  tasks = []
  for {assetName, sourceName} in assets
    fs.removeSync(path.join(buildDir, assetName))
    tasks.push(zip.bind(this, buildDir, sourceName, assetName))
  async.parallel(tasks, callback)

getRelease = (callback) ->
  options =
    uri: 'https://api.github.com/repos/atom/atom-master-builds/releases'
    method: 'GET'
    headers: defaultHeaders
    json: true
  request options, (error, response, releases=[]) ->
    if error? or response.statusCode isnt 200
      logError('Fetching releases failed', error, releases)
      callback(error ? new Error(response.statusCode))
    else
      if releases.length > maxReleases
        deleteRelease(release) for release in releases[maxReleases..]

      for release in releases when release.name is commitSha
        callback(null, release)
        return
      callback()

getAtomDraftRelease = (callback) ->
  atomRepo = new GitHub({repo: 'atom/atom', token})
  atomRepo.getReleases (error, releases=[]) ->
    if error?
      logError('Fetching atom/atom releases failed', error, releases)
      callback(error)
    else
      for release in releases when release.draft
        callback(null, release)
        return
      callback(new Error('No draft release in atom/atom repo'))

deleteRelease = (release) ->
  options =
    uri: release.url
    method: 'DELETE'
    headers: defaultHeaders
    json: true
  request options, (error, response, body='') ->
    if error? or response.statusCode isnt 204
      logError('Deleting release failed', error, body)

deleteExistingAssets = (release, assetNames, callback) ->
  [callback, assetNames] = [assetNames, callback] if not callback?

  deleteAsset = (url, callback) ->
    options =
      uri: url
      method: 'DELETE'
      headers: defaultHeaders
    request options, (error, response, body='') ->
      if error? or response.statusCode isnt 204
        logError('Deleting existing release asset failed', error, body)
        callback(error ? new Error(response.statusCode))
      else
        callback()

  tasks = []
  for asset in release.assets when not assetNames? or asset.name in assetNames
    tasks.push(deleteAsset.bind(this, asset.url))
  async.parallel(tasks, callback)

createBuildRelease = (callback) ->
  getRelease (error, release) ->
    if error?
      callback(error)
      return

    if release?
      deleteExistingAssets release, (error) ->
        callback(error, release)
      return

    options =
      uri: 'https://api.github.com/repos/atom/atom-master-builds/releases'
      method: 'POST'
      headers: defaultHeaders
      json:
        tag_name: "v#{commitSha}"
        target_commitish: 'master'
        name: commitSha
        body: "Build of [atom@#{commitSha.substring(0, 7)}](https://github.com/atom/atom/commits/#{commitSha})"
        draft: true
        prerelease: true
    request options, (error, response, release={}) ->
      if error? or response.statusCode isnt 201
        logError('Creating release failed', error, release)
        callback(error ? new Error(response.statusCode))
      else
        callback(null, release)

uploadAssets = (release, buildDir, assets, callback) ->
  upload = (release, assetName, assetPath, callback) ->
    options =
      uri: release.upload_url.replace(/\{.*$/, "?name=#{assetName}")
      method: 'POST'
      headers: _.extend({
        'Content-Type': 'application/zip'
        'Content-Length': fs.getSizeSync(assetPath)
        }, defaultHeaders)

    assetRequest = request options, (error, response, body='') ->
      if error? or response.statusCode >= 400
        logError("Upload release asset #{assetName} failed", error, body)
        callback(error ? new Error(response.statusCode))
      else
        callback(null, release)

    fs.createReadStream(assetPath).pipe(assetRequest)

  tasks = []
  for {assetName, sourceName} in assets
    assetPath = path.join(buildDir, assetName)
    tasks.push(upload.bind(this, release, assetName, assetPath))
  async.parallel(tasks, callback)

publishRelease = (release, callback) ->
  options =
    uri: release.url
    method: 'POST'
    headers: defaultHeaders
    json:
      draft: false
  request options, (error, response, body={}) ->
    if error? or response.statusCode isnt 200
      logError('Creating release failed', error, body)
      callback(error ? new Error(response.statusCode))
    else
      callback()
