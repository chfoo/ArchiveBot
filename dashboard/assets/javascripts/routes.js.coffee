Dashboard.Router.map ->
  @resource 'job', path: '/jobs/:job_id', ->
    @route 'history'
  @route 'history', path: '/histories/*url'

Dashboard.IndexRoute = Ember.Route.extend
  model: ->
    Dashboard.get 'messageProcessor'

Dashboard.JobRoute = Ember.Route.extend
  model: ->
    Dashboard.Job.create(url: 'http://www.w3schools.com/css3/css3_intro.asp')

Dashboard.HistoryRoute = Ember.Route.extend
  model: (params) ->
    m = Dashboard.JobHistory.create url: params['url']
    m.fetch().then -> m

  serialize: (model) ->
    { url: model.get 'url' }

  renderTemplate: ->
    @render 'job/history'

Dashboard.JobHistoryRoute = Ember.Route.extend
  model: ->
    m = Dashboard.JobHistory.create url: @modelFor('job').get('url')

    m.fetch().then -> m

# vim:ts=2:sw=2:et:tw=78
