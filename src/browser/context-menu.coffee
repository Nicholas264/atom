Menu = require 'menu'

module.exports =
class ContextMenu
  constructor: (template, @atomWindow) ->
    template = @createClickHandlers(template)
    menu = Menu.buildFromTemplate(template)
    menu.popup(@atomWindow.browserWindow)

  # It's necessary to build the event handlers in this process, otherwise
  # closures are drug across processes and failed to be garbage collected
  # appropriately.
  createClickHandlers: (template) ->
    for item in template
      if item.command
        (item.commandOptions ?= {}).contextCommand = true
        do (item) =>
          item.click = =>
            global.atomApplication.sendCommandToWindow(item.command, @atomWindow, item.commandOptions)
      item
