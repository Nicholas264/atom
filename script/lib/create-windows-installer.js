'use strict'

const electronInstaller = require('electron-winstaller')
const fs = require('fs')
const glob = require('glob')
const path = require('path')

const CONFIG = require('../config')

module.exports = (packagedAppPath) => {
  const archSuffix = process.arch === 'ia32' ? '' : '-' + process.arch
  const updateUrlPrefix = process.env.ATOM_UPDATE_URL_PREFIX || 'https://atom.io'
  const options = {
    appDirectory: packagedAppPath,
    authors: 'GitHub Inc.',
    iconUrl: `https://raw.githubusercontent.com/atom/atom/master/resources/app-icons/${CONFIG.channel}/atom.ico`,
    loadingGif: path.join(CONFIG.repositoryRootPath, 'resources', 'win', 'loading.gif'),
    outputDirectory: CONFIG.buildOutputPath,
    noMsi: true,
    noDelta: CONFIG.channel === 'nightly', // Delta packages are broken for nightly versions past nightly9 due to Squirrel/NuGet limitations
    remoteReleases: `${updateUrlPrefix}/api/updates${archSuffix}?version=${CONFIG.computedAppVersion}`,
    setupExe: `AtomSetup${process.arch === 'x64' ? '-x64' : ''}.exe`,
    setupIcon: path.join(CONFIG.repositoryRootPath, 'resources', 'app-icons', CONFIG.channel, 'atom.ico')
  }

  const cleanUp = () => {
    const releasesPath = `${CONFIG.buildOutputPath}/RELEASES`
    if (process.arch === 'x64' && fs.existsSync(releasesPath)) {
      fs.renameSync(releasesPath, `${releasesPath}-x64`)
    }

    for (let nupkgPath of glob.sync(`${CONFIG.buildOutputPath}/atom-*.nupkg`)) {
      if (!nupkgPath.includes(CONFIG.computedAppVersion)) {
        console.log(`Deleting downloaded nupkg for previous version at ${nupkgPath} to prevent it from being stored as an artifact`)
        fs.unlinkSync(nupkgPath)
      } else {
        if (process.arch === 'x64') {
          // Use the original .nupkg filename to generate the `atom-x64` name by inserting `-x64` after `atom`
          const newNupkgPath = nupkgPath.replace('atom-', 'atom-x64-')
          fs.renameSync(nupkgPath, newNupkgPath)
        }
      }
    }

    return `${CONFIG.buildOutputPath}/${options.setupExe}`
  }

  console.log(`Creating Windows Installer for ${packagedAppPath}`)
  return electronInstaller.createWindowsInstaller(options)
    .then(cleanUp, error => {
      cleanUp()
      return Promise.reject(error)
    })
}
