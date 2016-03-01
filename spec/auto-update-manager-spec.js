'use babel'

import AutoUpdateManager from '../src/auto-update-manager'
import {remote} from 'electron'
const electronAutoUpdater = remote.require('electron').autoUpdater

describe('AutoUpdateManager (renderer)', () => {
  let autoUpdateManager

  beforeEach(() => {
    autoUpdateManager = new AutoUpdateManager({
      applicationDelegate: atom.applicationDelegate
    })
  })

  afterEach(() => {
    autoUpdateManager.destroy()
  })

  describe('::onDidBeginCheckingForUpdate', () => {
    it('subscribes to "did-begin-checking-for-update" event', () => {
      const spy = jasmine.createSpy('spy')
      autoUpdateManager.onDidBeginCheckingForUpdate(spy)
      electronAutoUpdater.emit('checking-for-update')
      waitsFor(() => {
        return spy.callCount === 1
      })
    })
  })

  describe('::onDidBeginDownloadingUpdate', () => {
    it('subscribes to "did-begin-downloading-update" event', () => {
      const spy = jasmine.createSpy('spy')
      autoUpdateManager.onDidBeginDownloadingUpdate(spy)
      electronAutoUpdater.emit('update-available')
      waitsFor(() => {
        return spy.callCount === 1
      })
    })
  })

  describe('::onDidCompleteDownloadingUpdate', () => {
    it('subscribes to "did-complete-downloading-update" event', () => {
      const spy = jasmine.createSpy('spy')
      autoUpdateManager.onDidCompleteDownloadingUpdate(spy)
      electronAutoUpdater.emit('update-downloaded', null, null, '1.2.3')
      waitsFor(() => {
        return spy.callCount === 1
      })
      runs(() => {
        expect(spy.mostRecentCall.args[0].releaseVersion).toBe('1.2.3')
      })
    })
  })

  describe('::onUpdateNotAvailable', () => {
    it('subscribes to "update-not-available" event', () => {
      const spy = jasmine.createSpy('spy')
      autoUpdateManager.onUpdateNotAvailable(spy)
      electronAutoUpdater.emit('update-not-available')
      waitsFor(() => {
        return spy.callCount === 1
      })
    })
  })

  describe('::platformSupportsUpdates', () => {
    let state, releaseChannel
    it('returns true on OS X and Windows when in stable', () => {
      spyOn(autoUpdateManager, 'getState').andCallFake(() =>  state)
      spyOn(autoUpdateManager, 'getReleaseChannel').andCallFake(() => releaseChannel)

      state = 'idle'
      releaseChannel = 'stable'
      expect(autoUpdateManager.platformSupportsUpdates()).toBe(true)

      state = 'idle'
      releaseChannel = 'dev'
      expect(autoUpdateManager.platformSupportsUpdates()).toBe(false)

      state = 'unsupported'
      releaseChannel = 'stable'
      expect(autoUpdateManager.platformSupportsUpdates()).toBe(false)

      state = 'unsupported'
      releaseChannel = 'dev'
      expect(autoUpdateManager.platformSupportsUpdates()).toBe(false)
    })
  })

  describe('::destroy', () => {
    it('unsubscribes from all events', () => {
      const spy = jasmine.createSpy('spy')
      const doneIndicator = jasmine.createSpy('spy')
      atom.applicationDelegate.onUpdateNotAvailable(doneIndicator)
      autoUpdateManager.onDidBeginCheckingForUpdate(spy)
      autoUpdateManager.onDidBeginDownloadingUpdate(spy)
      autoUpdateManager.onDidCompleteDownloadingUpdate(spy)
      autoUpdateManager.onUpdateNotAvailable(spy)
      autoUpdateManager.destroy()
      electronAutoUpdater.emit('checking-for-update')
      electronAutoUpdater.emit('update-available')
      electronAutoUpdater.emit('update-downloaded', null, null, '1.2.3')
      electronAutoUpdater.emit('update-not-available')

      waitsFor(() => {
        return doneIndicator.callCount === 1
      })

      runs(() => {
        expect(spy.callCount).toBe(0)
      })
    })
  })
})
