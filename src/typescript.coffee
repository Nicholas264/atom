###
Cache for source code transpiled by TypeScript.

Inspired by https://github.com/atom/atom/blob/7a719d585db96ff7d2977db9067e1d9d4d0adf1a/src/babel.coffee
###

crypto = require 'crypto'
fs = require 'fs-plus'
path = require 'path'
tss = null # Defer until used

stats =
  hits: 0
  misses: 0

defaultOptions =
  target: 1
  module: 'commonjs'
  sourceMap: true

###
shasum - Hash with an update() method.
value - Must be a value that could be returned by JSON.parse().
###
updateDigestForJsonValue = (shasum, value) ->
  # Implmentation is similar to that of pretty-printing a JSON object, except:
  # * Strings are not escaped.
  # * No effort is made to avoid trailing commas.
  # These shortcuts should not affect the correctness of this function.
  type = typeof value
  if type is 'string'
    shasum.update('"', 'utf8')
    shasum.update(value, 'utf8')
    shasum.update('"', 'utf8')
  else if type in ['boolean', 'number']
    shasum.update(value.toString(), 'utf8')
  else if value is null
    shasum.update('null', 'utf8')
  else if Array.isArray value
    shasum.update('[', 'utf8')
    for item in value
      updateDigestForJsonValue(shasum, item)
      shasum.update(',', 'utf8')
    shasum.update(']', 'utf8')
  else
    # value must be an object: be sure to sort the keys.
    keys = Object.keys value
    keys.sort()

    shasum.update('{', 'utf8')
    for key in keys
      updateDigestForJsonValue(shasum, key)
      shasum.update(': ', 'utf8')
      updateDigestForJsonValue(shasum, value[key])
      shasum.update(',', 'utf8')
    shasum.update('}', 'utf8')

createTypeScriptVersionAndOptionsDigest = (version, options) ->
  shasum = crypto.createHash('sha1')
  # Include the version of typescript in the hash.
  shasum.update('typescript', 'utf8')
  shasum.update('\0', 'utf8')
  shasum.update(version, 'utf8')
  shasum.update('\0', 'utf8')
  updateDigestForJsonValue(shasum, options)
  shasum.digest('hex')

cacheDir = null
jsCacheDir = null

getCachePath = (sourceCode) ->
  digest = crypto.createHash('sha1').update(sourceCode, 'utf8').digest('hex')

  unless jsCacheDir?
    tsVersion = require('typescript/package.json').version
    jsCacheDir = path.join(cacheDir, createTypeScriptVersionAndOptionsDigest(tsVersion, defaultOptions))

  path.join(jsCacheDir, "#{digest}.js")

getCachedJavaScript = (cachePath) ->
  if fs.isFileSync(cachePath)
    try
      cachedJavaScript = fs.readFileSync(cachePath, 'utf8')
      stats.hits++
      return cachedJavaScript
  null

# Returns the TypeScript options that should be used to transpile filePath.
createOptions = (filePath) ->
  options = filename: filePath
  for key, value of defaultOptions
    options[key] = value
  options

transpile = (sourceCode, filePath, cachePath) ->
  options = createOptions(filePath)
  tss ?= new (require './typescript-transpile').TypeScriptSimple(options, false)
  js = tss.compile(sourceCode, filePath)
  stats.misses++

  try
    fs.writeFileSync(cachePath, js)

  js

# Function that obeys the contract of an entry in the require.extensions map.
# Returns the transpiled version of the JavaScript code at filePath, which is
# either generated on the fly or pulled from cache.
loadFile = (module, filePath) ->
  sourceCode = fs.readFileSync(filePath, 'utf8')
  cachePath = getCachePath(sourceCode)
  js = getCachedJavaScript(cachePath) ? transpile(sourceCode, filePath, cachePath)
  module._compile(js, filePath)

register = ->
  Object.defineProperty(require.extensions, '.ts', {
    enumerable: true
    writable: false
    value: loadFile
  })

setCacheDirectory = (newCacheDir) ->
  if cacheDir isnt newCacheDir
    cacheDir = newCacheDir
    jsCacheDir = null

module.exports =
  register: register
  setCacheDirectory: setCacheDirectory
  getCacheMisses: -> stats.misses
  getCacheHits: -> stats.hits

  # Visible for testing.
  createTypeScriptVersionAndOptionsDigest: createTypeScriptVersionAndOptionsDigest

  addPathToCache: (filePath) ->
    return if path.extname(filePath) isnt '.ts'

    sourceCode = fs.readFileSync(filePath, 'utf8')
    cachePath = getCachePath(sourceCode)
    transpile(sourceCode, filePath, cachePath)
