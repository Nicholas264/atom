'use strict'

const assert = require('assert')
const fs = require('fs-extra')
const path = require('path')
const childProcess = require('child_process')
const electronPackager = require('electron-packager')
const includePathInPackagedApp = require('./include-path-in-packaged-app')
const getLicenseText = require('./get-license-text')

const CONFIG = require('../config')

module.exports = function () {
  const appName = getAppName()
  console.log(`Running electron-packager on ${CONFIG.intermediateAppPath} with app name "${appName}"`)
  return runPackager({
    'app-version': CONFIG.appMetadata.version,
    'app-bundle-id': 'com.github.atom',
    'app-copyright': `Copyright (C) ${(new Date()).getFullYear()} GitHub, Inc. All rights reserved`,
    'arch': process.arch,
    'asar': {unpack: buildAsarUnpackGlobExpression()},
    'build-version': CONFIG.appMetadata.version,
    'download': {cache: CONFIG.cachePath},
    'dir': CONFIG.intermediateAppPath,
    'helper-bundle-id': 'com.github.atom.helper',
    'icon': getIcon(),
    'name': appName,
    'out': CONFIG.buildOutputPath,
    'overwrite': true,
    'platform': process.platform,
    'version': CONFIG.appMetadata.electronVersion,
    'version-string': {
      CompanyName: 'GitHub, Inc.',
      FileDescription: 'Atom',
      ProductName: 'Atom',
    }
  }).then((packagedAppPath) => {
    let bundledResourcesPath
    if (process.platform === 'darwin') {
      bundledResourcesPath = path.join(packagedAppPath, 'Contents', 'Resources')
      setAtomHelperVersion(packagedAppPath)
    } else {
      bundledResourcesPath = path.join(packagedAppPath, 'resources')
    }

    return copyNonASARResources(packagedAppPath, bundledResourcesPath).then(() => {
      console.log(`Application bundle created at ${packagedAppPath}`)
      return packagedAppPath
    })
  })
}

function copyNonASARResources (packagedAppPath, bundledResourcesPath) {
  console.log(`Copying non-ASAR resources to ${bundledResourcesPath}`)
  fs.copySync(
    path.join(CONFIG.repositoryRootPath, 'apm', 'node_modules', 'atom-package-manager'),
    path.join(bundledResourcesPath, 'app', 'apm'),
    {filter: includePathInPackagedApp}
  )
  if (process.platform !== 'win32') {
    // Existing symlinks on user systems point to an outdated path, so just symlink it to the real location of the apm binary.
    // TODO: Change command installer to point to appropriate path and remove this fallback after a few releases.
    fs.symlinkSync(path.join('..', '..', 'bin', 'apm'), path.join(bundledResourcesPath, 'app', 'apm', 'node_modules', '.bin', 'apm'))
    fs.copySync(path.join(CONFIG.repositoryRootPath, 'atom.sh'), path.join(bundledResourcesPath, 'app', 'atom.sh'))
  }
  if (process.platform === 'darwin') {
    fs.copySync(path.join(CONFIG.repositoryRootPath, 'resources', 'mac', 'file.icns'), path.join(bundledResourcesPath, 'file.icns'))
  } else if (process.platform === 'linux') {
    fs.copySync(path.join(CONFIG.repositoryRootPath, 'resources', 'app-icons', CONFIG.channel, 'png', '1024.png'), path.join(packagedAppPath, 'atom.png'))
  } else if (process.platform === 'win32') {
    fs.copySync(path.join('resources', 'win', 'atom.cmd'), path.join(bundledResourcesPath, 'cli', 'atom.cmd'))
    fs.copySync(path.join('resources', 'win', 'atom.sh'), path.join(bundledResourcesPath, 'cli', 'atom.sh'))
    fs.copySync(path.join('resources', 'win', 'atom.js'), path.join(bundledResourcesPath, 'cli', 'atom.js'))
    fs.copySync(path.join('resources', 'win', 'apm.cmd'), path.join(bundledResourcesPath, 'cli', 'apm.cmd'))
    fs.copySync(path.join('resources', 'win', 'apm.sh'), path.join(bundledResourcesPath, 'cli', 'apm.sh'))
  }

  console.log(`Writing LICENSE.md to ${bundledResourcesPath}`)
  return getLicenseText().then((licenseText) => {
    fs.writeFileSync(path.join(bundledResourcesPath, 'LICENSE.md'), licenseText)
  })
}

function setAtomHelperVersion (packagedAppPath) {
  const frameworksPath = path.join(packagedAppPath, 'Contents', 'Frameworks')
  const helperPListPath = path.join(frameworksPath, 'Atom Helper.app', 'Contents', 'Info.plist')
  console.log(`Setting Atom Helper Version for ${helperPListPath}`)
  childProcess.spawnSync('/usr/libexec/PlistBuddy', ['-c', 'Set CFBundleVersion', CONFIG.appMetadata.version, helperPListPath])
  childProcess.spawnSync('/usr/libexec/PlistBuddy', ['-c', 'Set CFBundleShortVersionString', CONFIG.appMetadata.version, helperPListPath])
}

function buildAsarUnpackGlobExpression () {
  const unpack = [
    '*.node',
    'ctags-config',
    'ctags-darwin',
    'ctags-linux',
    'ctags-win32.exe',
    path.join('**', 'node_modules', 'spellchecker', '**'),
    path.join('**', 'resources', 'atom.png')
  ]

  return `{${unpack.join(',')}}`
}

function getAppName () {
  if (process.platform === 'darwin') {
    return CONFIG.channel === 'beta' ? 'Atom Beta' : 'Atom'
  } else {
    return 'atom'
  }
}

function getIcon () {
  switch (process.platform) {
    case 'darwin':
      return path.join(CONFIG.repositoryRootPath, 'resources', 'app-icons', CONFIG.channel, 'atom.icns')
    case 'linux':
      // Don't pass an icon, as the dock/window list icon is set via the icon
      // option in the BrowserWindow constructor in atom-window.coffee.
      return null
    default:
      return path.join(CONFIG.repositoryRootPath, 'resources', 'app-icons', CONFIG.channel, 'atom.ico')
  }
}

function runPackager (options) {
  return new Promise((resolve, reject) => {
    electronPackager(options, (err, packageOutputDirPaths) => {
      if (err) {
        reject(err)
        throw new Error(err)
      } else {
        assert(packageOutputDirPaths.length === 1, 'Generated more than one electron application!')
        const packagedAppPath = renamePackagedAppDir(packageOutputDirPaths[0])
        resolve(packagedAppPath)
      }
    })
  })
}

function renamePackagedAppDir (packageOutputDirPath) {
  let packagedAppPath
  if (process.platform === 'darwin') {
    const appBundleName = getAppName() + '.app'
    packagedAppPath = path.join(CONFIG.buildOutputPath, appBundleName)
    if (fs.existsSync(packagedAppPath)) fs.removeSync(packagedAppPath)
    fs.renameSync(path.join(packageOutputDirPath, appBundleName), packagedAppPath)
  } else if (process.platform === 'linux') {
    const appName = CONFIG.channel === 'beta' ? 'atom-beta' : 'atom'
    let architecture
    if (process.arch === 'ia32') {
      architecture = 'i386'
    } else if (process.arch === 'x64') {
      architecture = 'amd64'
    } else {
      architecture = process.arch
    }
    packagedAppPath = path.join(CONFIG.buildOutputPath, `${appName}-${CONFIG.appMetadata.version}-${architecture}`)
    if (fs.existsSync(packagedAppPath)) fs.removeSync(packagedAppPath)
    fs.renameSync(packageOutputDirPath, packagedAppPath)
  } else {
    const appName = CONFIG.channel === 'beta' ? 'Atom Beta' : 'Atom'
    packagedAppPath = path.join(CONFIG.buildOutputPath, appName)
    if (fs.existsSync(packagedAppPath)) fs.removeSync(packagedAppPath)
    fs.renameSync(packageOutputDirPath, packagedAppPath)
  }
  return packagedAppPath
}
