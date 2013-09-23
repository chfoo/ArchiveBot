require 'celluloid'
require 'celluloid-redis'
require 'reel'
require 'trollop'
require 'uri'
require 'webmachine'

require File.expand_path('../job', __FILE__)
require File.expand_path('../log_update_listener', __FILE__)

opts = Trollop.options do
  opt :url, 'URL to bind to', :default => 'http://localhost:4567'
  opt :redis, 'URL of Redis server', :default => ENV['REDIS_URL'] || 'redis://localhost:6379/0'
  opt :log_update_channel, 'Redis pubsub channel for log updates', :default => ENV['LOG_CHANNEL'] || 'updates'
end

bind_uri = URI.parse(opts[:url])

# An update packet.
class Update
  # The work item's internal ID.
  attr_accessor :ident

  # The work item's URL.
  attr_accessor :url

  # Response code counts.
  attr_accessor :r1xx, :r2xx, :r3xx, :r4xx, :r5xx, :runk

  # The latest URL fetched from the work item, its HTTP response code, and
  # wget's interpretation of the result.
  attr_accessor :last_fetched_url, :last_fetched_response_code,
    :last_fetched_wget_code

  def initialize(values = {})
    values.each do |k, v|
      send("#{k}=", v)
    end
  end
end

# Receives messages from the log update pubsub channel, fetches log messages
# and relevant data, and sends said data out to all connected clients.
class LogReceiver < LogUpdateListener
  def on_receive(ident)
  end
end

# The Dashboard resource.  This serves up a giant glob of Javascript and CSS,
# with a smattering of HTML.
class Dashboard < Webmachine::Resource
  def to_html
  end
end

# The skin holding it all in.
App = Webmachine::Application.new do |app|
  app.routes do
    add [], Dashboard
  end

  app.configure do |config|
    config.ip = bind_uri.host
    config.port = bind_uri.port
    config.adapter = :Reel

    config.adapter_options[:websocket_handler] = proc do |websocket|

    end
  end
end

App.run
