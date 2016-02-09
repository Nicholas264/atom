/** @babel */
import {it, fit, ffit, fffit, beforeEach, afterEach} from './async-spec-helpers'

const StateStore = require('../src/state-store.js')

describe("StateStore", () => {
  let databaseName = `test-database-${Date.now()}`
  let version = 1

  it("can save and load states", () => {
    const store = new StateStore(databaseName, version)
    return store.save('key', {foo:'bar'})
      .then(() => store.load('key'))
      .then((state) => {
        expect(state).toEqual({foo:'bar'})
      })
  })

  it("resolves with null when a non-existent key is loaded", () => {
    const store = new StateStore(databaseName, version)
    return store.load('no-such-key').then((value) => {
      expect(value).toBeNull()
    })
  });

  describe("when there is an error reading from the database", () => {
    it("rejects the promise returned by load", () => {
      const store = new StateStore(databaseName, version)

      const fakeErrorEvent = {target: {errorCode: "Something bad happened"}}

      spyOn(IDBObjectStore.prototype, 'get').andCallFake((key) => {
        let request = {}
        process.nextTick(() => request.onerror(fakeErrorEvent))
        return request
      })

      return store.load('nonexistentKey')
        .then(() => {
          throw new Error("Promise should have been rejected")
        })
        .catch((event) => {
          expect(event).toBe(fakeErrorEvent)
        })
    })
  })
})
