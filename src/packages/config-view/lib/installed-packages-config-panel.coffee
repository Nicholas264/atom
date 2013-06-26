$ = require 'jquery'
_ = require 'underscore'
{View} = require 'space-pen'
ConfigPanel = require './config-panel'
PackageConfigView = require './package-config-view'
packageManager = require './package-manager'
stringScore = require 'stringscore'

### Internal ###
module.exports =
class InstalledPackagesConfigPanel extends View
  @content: ->
    @div class: 'installed-packages', =>
      @div outlet: 'loadingArea', class: 'alert alert-info loading-area', =>
        @span 'Loading installed packages\u2026'
      @div outlet: 'packagesArea'

  initialize: (@packageEventEmitter) ->
    @packages = _.sortBy(atom.getAvailablePackageMetadata(), 'name')
    packageManager.renderMarkdownInMetadata @packages, =>
      @loadingArea.hide()
      for pack in @packages
        @packagesArea.append(new PackageConfigView(pack, @packageEventEmitter))
      @packageEventEmitter.trigger 'installed-packages-loaded', [@packages]

    @packageEventEmitter.on 'package-installed', (error, pack) =>
      @addPackage(pack) unless error?
    @packageEventEmitter.on 'package-uninstalled', (error, pack) =>
      @removePackage(pack) unless error?

  removePackage: ({name}) ->
    @packages = _.reject @packages, (pack) -> pack.name is name
    @packagesArea.children("[name=#{name}]").remove()

  addPackage: (pack) ->
    @packages.push(pack)
    @packages = _.sortBy(@packages, 'name')
    index = @packages.indexOf(pack)
    view = new PackageConfigView(pack, @packageEventEmitter)
    if index is 0
      @packagesArea.prepend(view)
    else if index is @packages.length - 1
      @packagesArea.append(view)
    else
      @packagesArea.children(":eq(#{index})").before(view)

  filterPackages: (filterString) ->
    packageViews = @packagesArea.children()
    for packageView in packageViews
      if /^\s*$/.test(filterString) or stringScore(packageView.getAttribute('name'), filterString)
        $(packageView).show()
      else
        $(packageView).hide()

  getPackageCount: -> @packages.length
