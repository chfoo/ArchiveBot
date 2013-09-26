Dashboard.JobView = Ember.View.extend
  classNameBindings: ['finished']
  classNames: ['job']

  tagName: 'article'

  hideWhenFinished: (->
    @$().on 'transitionend webkitTransitionEnd oTransitionEnd otransitionend', =>
      @remove()
      @get('jobList').unregisterJob @get('ident')
  ).observes('finished')

Dashboard.ProportionView = Ember.View.extend
  classNames: ['success-bar']

  templateName: 'proportion-view'

  tagName: 'div'

  didInsertElement: ->
    @sizeBars()

  onProportionChange: (->
    @sizeBars()
  ).observes('okPercentage', 'errorPercentage')

  sizeBars: ->
    @$('.ok').css { width: @get('okPercentage') + '%' }
    @$('.error').css { width: @get('errorPercentage') + '%' }

Dashboard.LogView = Ember.View.extend
  classNames: ['terminal', 'log-view']

  templateName: 'log-view'

  tagName: 'section'

  maxSize: 512

  didInsertElement: ->
    @refreshBuffer()

  onIncomingChange: (->
    @refreshBuffer()
  ).observes('incoming', 'maxSize')

  refreshBuffer: ->
    buf = @get 'eventBuffer'
    maxSize = @get 'maxSize'
    incoming = @get('incoming') || []

    if !buf
      @set 'eventBuffer', []
      buf = @get 'eventBuffer'

    buf.pushObjects incoming
    
    if buf.length > maxSize
      overage = buf.length - maxSize
      buf.removeAt 0, overage

    if @get('autoScroll')
      Ember.run.next =>
        container = @$()
        container.scrollTop container.prop('scrollHeight')

# vim:ts=2:sw=2:et:tw=78
