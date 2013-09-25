window.Dashboard = Ember.Application.create()

# ----------------------------------------------------------------------------
# MODELS
# ----------------------------------------------------------------------------

Dashboard.Job = Ember.Object.extend
  okPercentage: (->
    total = @get 'total'
    errored = @get 'error_count'

    100 * ((total - errored) / total)
  ).property('total', 'error_count')

  errorPercentage: (->
    total = @get 'total'
    errored = @get 'error_count'

    100 * (errored / total)
  ).property('total', 'error_count')

  mibDownloaded: (->
    (@get('bytes_downloaded') / (1024 * 1024)).toFixed(2)
  ).property('bytes_downloaded')

  urlForDisplay: (->
    url = @get 'url'

    if url && url.length > 63
      url.slice(0, 61) + '...'
    else
      url
  ).property('url')

  generateCompletionMessage: (->
    if @get('completed')
      entry = Ember.Object.create
        text: 'Job completed'
        classNames: 'completed'

      @addLogEntries [entry]
  ).observes('completed')

  generateAbortMessage: (->
    if @get('aborted')
      entry = Ember.Object.create
        text: 'Job aborted'
        classNames: 'aborted'

      @addLogEntries [entry]
  ).observes('aborted')

  addLogEntries: (entries) ->
    @set 'latestEntries', entries

  finished: (->
    @get('aborted') || @get('completed')
  ).property('aborted', 'completed')

Dashboard.History = Ember.Object.extend
  fetch: ->
    $.getJSON(@get 'path').then(=>

    )

Dashboard.DownloadUpdateEntry = Ember.Object.extend
  classNames: (->
    classes = []

    classes.pushObject('warning') if @get('is_warning')
    classes.pushObject('error') if @get('is_error')

    classes
  ).property('is_warning', 'is_error')

  text: (->
    [@get('response_code'), @get('wget_code'), @get('url')].join(' ')
  ).property('response_code', 'wget_code', 'url')

Dashboard.MessageProcessor = Ember.Object.extend
  registerJob: (ident) ->
    job = Dashboard.Job.create autoScroll: true

    @get('jobIndex')[ident] = job
    @get('jobs').pushObject job

    job

  unregisterJob: (ident) ->
    job = @get('jobIndex')[ident]

    return unless job?

    index = @get('jobs').indexOf job
    @get('jobs').removeAt(index) if index != -1

    delete @get('jobIndex')[ident]

  process: (data) ->
    json = JSON.parse data
    ident = json['ident']
    type = json['type']

    # Sanity-check the message.
    console.log 'Message is malformed (no ident)' unless ident?
    console.log 'Message is malformed (no type identifier)' unless type?

    # Do we have a job for the identifier?
    # If we don't, register a job and retry processing when the run loop
    # comes around again.
    job = @get('jobIndex')[ident]

    if !job?
      @registerJob ident

      Ember.run.next =>
        @process data

      return

    # If we do, process the message.
    switch json['type']
      when 'status_change' then @processStatusChange(json, job)
      when 'download_update' then @processDownloadUpdate(json, job)
      else console.log "Can't handle message type #{json['type']}"

  processStatusChange: (json, job) ->
    job.setProperties
      aborted: json['aborted']
      completed: json['completed']

  directCopiedProperties: [
    'url', 'ident',
    'r1xx', 'r2xx', 'r3xx', 'r4xx', 'r5xx', 'runk',
    'total', 'error_count',
    'bytes_downloaded'
  ]

  processDownloadUpdate: (json, job) ->
    props = {}
    props[key] = json[key] for key in @directCopiedProperties
    job.setProperties props

    job.addLogEntries(json['entries'].map (item) ->
      Dashboard.DownloadUpdateEntry.create(item)
    )

messageProcessor = Dashboard.MessageProcessor.create
  jobIndex: {}
  jobs: []

Dashboard.messageProcessor = messageProcessor

# -------------------------------------------------------------------------
# ROUTES
# -------------------------------------------------------------------------

Dashboard.Router.map ->
  @resource 'history', path: '/histories/*url'

Dashboard.IndexRoute = Ember.Route.extend
  model: ->
    messageProcessor

Dashboard.HistoryRoute = Ember.Route.extend
  model: (params) ->
    model = Dashboard.History.create
      url: params['url']

    model.fetch().then ->
      model

  serialize: (model) ->
    { url: model.get 'url' }

# -------------------------------------------------------------------------
# CONTROLLERS
# -------------------------------------------------------------------------

Dashboard.IndexController = Ember.Controller.extend
  needs: ['processor']

  jobsBinding: 'controllers.processor.content'

Dashboard.ProcessorController = Ember.ArrayController.extend
  content: messageProcessor.get 'jobs'

# -------------------------------------------------------------------------
# VIEWS
# -------------------------------------------------------------------------

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
