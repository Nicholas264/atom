const {Emitter, CompositeDisposable} = require('event-kit')

module.exports = class PanelContainer {
  constructor ({location} = {}) {
    this.location = location
    this.emitter = new Emitter()
    this.subscriptions = new CompositeDisposable()
    this.panels = []
  }

  destroy () {
    for (let panel of this.getPanels()) { panel.destroy() }
    this.subscriptions.dispose()
    this.emitter.emit('did-destroy', this)
    return this.emitter.dispose()
  }

  /*
  Section: Event Subscription
  */

  onDidAddPanel (callback) {
    return this.emitter.on('did-add-panel', callback)
  }

  onDidRemovePanel (callback) {
    return this.emitter.on('did-remove-panel', callback)
  }

  onDidDestroy (callback) {
    return this.emitter.on('did-destroy', callback)
  }

  /*
  Section: Panels
  */

  getLocation () { return this.location }

  isModal () { return this.location === 'modal' }

  getPanels () { return this.panels.slice() }

  addPanel (panel) {
    this.subscriptions.add(panel.onDidDestroy(this.panelDestroyed.bind(this)))

    const index = this.getPanelIndex(panel)
    if (index === this.panels.length) {
      this.panels.push(panel)
    } else {
      this.panels.splice(index, 0, panel)
    }

    this.emitter.emit('did-add-panel', {panel, index})
    return panel
  }

  panelForItem (item) {
    for (let panel of this.panels) {
      if (panel.getItem() === item) { return panel }
    }
    return null
  }

  panelDestroyed (panel) {
    const index = this.panels.indexOf(panel)
    if (index > -1) {
      this.panels.splice(index, 1)
      return this.emitter.emit('did-remove-panel', {panel, index})
    }
  }

  getPanelIndex (panel) {
    let i, p
    const priority = panel.getPriority()
    if (['bottom', 'right'].includes(this.location)) {
      for (i = this.panels.length - 1; i >= 0; i--) {
        p = this.panels[i]
        if (priority < p.getPriority()) { return i + 1 }
      }
      return 0
    } else {
      for (i = 0; i < this.panels.length; i++) {
        p = this.panels[i]
        if (priority < p.getPriority()) { return i }
      }
      return this.panels.length
    }
  }
}
