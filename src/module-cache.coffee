Module = require 'module'
path = require 'path'
fs = require 'fs-plus'
semver = require 'semver'

nativeModules = process.binding('natives')

loadDependencies = (modulePath, rootPath, rootMetadata, moduleCache) ->
  nodeModulesPath = path.join(modulePath, 'node_modules')
  for childPath in fs.listSync(nodeModulesPath)
    continue if path.basename(childPath) is '.bin'
    continue if rootPath is modulePath and rootMetadata.packageDependencies?.hasOwnProperty(path.basename(childPath))

    childMetadataPath = path.join(childPath, 'package.json')
    continue unless fs.isFileSync(childMetadataPath)

    childMetadata = JSON.parse(fs.readFileSync(childMetadataPath))
    if childMetadata?.version
      try
        mainPath = require.resolve(childPath)
      catch error
        console.log "Skipping #{childPath}, no main module"

      if mainPath
        moduleCache.dependencies.push
          name: childMetadata.name
          version: childMetadata.version
          path: path.relative(rootPath, mainPath)

      loadDependencies(childPath, rootPath, rootMetadata, moduleCache)

loadFolderCompatibility = (modulePath, rootPath, rootMetadata, moduleCache) ->
  metadataPath = path.join(modulePath, 'package.json')
  return unless fs.isFileSync(metadataPath)

  nodeModulesPath = path.join(modulePath, 'node_modules')
  dependencies = JSON.parse(fs.readFileSync(metadataPath))?.dependencies ? {}

  onDirectory = (childPath) ->
    path.basename(childPath) isnt 'node_modules'

  extensions = Object.keys(require.extensions)
  paths = {}
  onFile = (childPath) ->
    if path.extname(childPath) in extensions
      relativePath = path.relative(rootPath, path.dirname(childPath))
      paths[relativePath] = true
  fs.traverseTreeSync(modulePath, onFile, onDirectory)

  paths = Object.keys(paths)
  if paths.length > 0 and Object.keys(dependencies).length > 0
    moduleCache.folders.push({paths, dependencies})

  for childPath in fs.listSync(nodeModulesPath)
    continue if path.basename(childPath) is '.bin'
    continue if rootPath is modulePath and rootMetadata.packageDependencies?.hasOwnProperty(path.basename(childPath))

    loadFolderCompatibility(childPath, rootPath, rootMetadata, moduleCache)

exports.generateDependencies = (modulePath) ->
  metadataPath = path.join(modulePath, 'package.json')
  metadata = JSON.parse(fs.readFileSync(metadataPath))

  moduleCache =
    version: 1
    dependencies: []
    folders: []

  loadDependencies(modulePath, modulePath, metadata, moduleCache)
  loadFolderCompatibility(modulePath, modulePath, metadata, moduleCache)

  metadata._atomModuleCache = moduleCache
  fs.writeFileSync(metadataPath, JSON.stringify(metadata, null, 2))

getCachedModulePath = (relativePath, parentModule) ->
  return unless relativePath
  return unless parentModule?.id

  return if nativeModules.hasOwnProperty(relativePath)
  return if relativePath[0] is '.'
  return if relativePath[relativePath.length - 1] is '/'
  return if fs.isAbsolute(relativePath)

  folderPath = path.dirname(parentModule.id)

  dependency = folders[folderPath]?[relativePath]
  return unless dependency?

  candidates = dependencies[relativePath]
  return unless candidates?

  for version, resolvedPath of candidates
    if Module._cache[resolvedPath] and semver.satisfies(version, dependency)
      return resolvedPath

  undefined

registered = false
exports.register = ->
  return if registered

  originalResolveFilename = Module._resolveFilename
  Module._resolveFilename = (relativePath, parentModule) ->
    resolvedPath = getCachedModulePath(relativePath, parentModule)
    resolvedPath ? originalResolveFilename(relativePath, parentModule)
  registered = true

dependencies = {}
folders = {}

global.mc = {dependencies, folders}

exports.add = (directoryPath) ->
  cache = require(path.join(directoryPath, 'package.json'))?._atomModuleCache
  for dependency in cache?.dependencies ? []
    dependencies[dependency.name] ?= {}
    dependencies[dependency.name][dependency.version] = path.join(directoryPath, dependency.path)

  for entry in cache?.folders ? []
    for folderPath in entry.paths
      folders[path.join(directoryPath, folderPath)] = entry.dependencies
