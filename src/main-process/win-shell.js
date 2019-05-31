const Registry = require('winreg')
const Path = require('path')

let exeName = Path.basename(process.execPath)
let appPath = `"${process.execPath}"`
let fileIconPath = `"${Path.join(process.execPath, '..', 'resources', 'cli', 'file.ico')}"`

class ShellOption {
  constructor (key, parts) {
    this.isRegistered = this.isRegistered.bind(this)
    this.register = this.register.bind(this)
    this.deregister = this.deregister.bind(this)
    this.update = this.update.bind(this)
    this.key = key
    this.parts = parts
  }

  isRegistered (callback) {
    new Registry({hive: 'HKCU', key: `${this.key}\\${this.parts[0].key}`})
      .get(this.parts[0].name, (err, val) => callback((err == null) && (val != null) && val.value === this.parts[0].value))
  }

  register (callback) {
    let doneCount = this.parts.length
    this.parts.forEach(part => {
      let reg = new Registry({hive: 'HKCU', key: (part.key != null) ? `${this.key}\\${part.key}` : this.key})
      return reg.create(() => reg.set(part.name, Registry.REG_SZ, part.value, () => { if (--doneCount === 0) return callback() }))
    })
  }

  deregister (callback) {
    this.isRegistered(isRegistered => {
      if (isRegistered) {
        new Registry({hive: 'HKCU', key: this.key}).destroy(() => callback(null, true))
      } else {
        callback(null, false)
      }
    })
  }

  update (callback) {
    new Registry({hive: 'HKCU', key: `${this.key}\\${this.parts[0].key}`})
      .get(this.parts[0].name, (err, val) => {
        if ((err != null) || (val == null)) {
          callback(err)
        } else {
          this.register(callback)
        }
      })
  }
}

function getShellOptions (appName) {
  const contextParts = [
      {key: 'command', name: '', value: `${appPath} "%1"`},
      {name: '', value: `Open with ${appName}`},
      {name: 'Icon', value: `${appPath}`}
  ]

  return {
    fileHandler: new ShellOption(`\\Software\\Classes\\Applications\\${exeName}`,
      [
        {key: 'shell\\open\\command', name: '', value: `${appPath} "%1"`},
        {key: 'shell\\open', name: 'FriendlyAppName', value: `${appName}`},
        {key: 'DefaultIcon', name: '', value: `${fileIconPath}`}
      ]
    ),
    fileContextMenu: new ShellOption(`\\Software\\Classes\\*\\shell\\${appName}`, contextParts),
    folderContextMenu: new ShellOption(`\\Software\\Classes\\Directory\\shell\\${appName}`, contextParts),
    folderBackgroundContextMenu: new ShellOption(`\\Software\\Classes\\Directory\\background\\shell\\${appName}`,
      JSON.parse(JSON.stringify(contextParts).replace('%1', '%V'))
    )
  }
}

function registerShellIntegration (appName, callback) {
  const shellOptions = getShellOptions(appName)
  shellOptions.fileHandler.register(() =>
    shellOptions.fileContextMenu.update(() =>
      shellOptions.folderContextMenu.update(() =>
        shellOptions.folderBackgroundContextMenu.update(() => callback())
      )
    )
  )
}

function updateShellIntegration (appName, callback) {
  const shellOptions = getShellOptions(appName)
  shellOptions.fileHandler.update(() =>
    shellOptions.fileContextMenu.update(() =>
      shellOptions.folderContextMenu.update(() =>
        shellOptions.folderBackgroundContextMenu.update(() => callback())
      )
    )
  )
}

function deregisterShellIntegration (appName, callback) {
  const shellOptions = getShellOptions(appName)
  shellOptions.fileHandler.deregister(() =>
    shellOptions.fileContextMenu.deregister(() =>
      shellOptions.folderContextMenu.deregister(() =>
        shellOptions.folderBackgroundContextMenu.deregister(() => callback())
      )
    )
  )
}

module.exports = {
  registerShellIntegration,
  updateShellIntegration,
  deregisterShellIntegration
}
