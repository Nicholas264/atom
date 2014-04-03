{React, div} = require 'reactionary'
SubscriberMixin = require './subscriber-mixin'

module.exports =
SelectionComponent = React.createClass
  mixins: [SubscriberMixin]

  render: ->
    div className: 'selection',
      for regionRect, i in @props.selection.getRegionRects()
        div className: 'region', key: i, style: regionRect

  componentDidMount: ->
    @subscribe @props.selection, 'screen-range-changed', => @forceUpdate()

  componentWillUnmount: ->
    @unsubscribe()
