archivebot = {}

dofile("acceptance_heuristics.lua")
dofile("redis_script_exec.lua")
dofile("settings.lua")

require('socket')

local json = require('json')
local redis = require('vendor/redis-lua/src/redis')
local ident = os.getenv('ITEM_IDENT')
local rconn = redis.connect(os.getenv('REDIS_HOST'), os.getenv('REDIS_PORT'))
local aborter = os.getenv('ABORT_SCRIPT')
local log_key = os.getenv('LOG_KEY')
local log_channel = os.getenv('LOG_CHANNEL')

local do_abort = eval_redis(os.getenv('ABORT_SCRIPT'), rconn)
local do_log = eval_redis(os.getenv('LOG_SCRIPT'), rconn)

rconn:select(os.getenv('REDIS_DB'))

-- Generates a log entry for ignored URLs.
local log_ignored_url = function(url, pattern)
  local entry = {
    ts = os.time(),
    url = url,
    pattern = pattern,
    type = 'ignore'
  }

  do_log(1, ident, json.encode(entry), log_channel, log_key)
end

local requisite_urls = {}

local add_as_page_requisite = function(url)
  requisite_urls[url] = true
end

wpull_hook.callbacks.accept_url = function(url_info, record_info, verdict, reasons)
  -- Does the URL match any of the ignore patterns?
  local pattern = archivebot.ignore_url_p(url_info.url)

  if pattern then
    log_ignored_url(url_info.url, pattern)
    return false
  end

  -- Second-guess wget's host-spanning restrictions.
  if not verdict and is_span_host_filter_failed_only(reasons.filters) then
    -- Is the parent a www.example.com and the child an example.com, or vice
    -- versa?
    if record_info.referrer_info and 
    is_www_to_bare(record_info.referrer_info, url_info) then
      -- OK, grab it after all.
      return true
    end

    -- Is this a URL of a non-hyperlinked page requisite?
    if is_page_requisite(record_info) then
      -- Yeah, grab these too.  We also flag the URL as a page requisite here
      -- because we'll need to know that when we calculate the post-request
      -- delay.
      add_as_page_requisite(url_info.url)
      return true
    end
  end

  -- If we're looking at a page requisite that didn't require verdict
  -- override, flag it as a requisite.
  if verdict and is_page_requisite(record_info) then
    add_as_page_requisite(url_info.url)
  end

  -- If we get here, none of our exceptions apply.  Return the original
  -- verdict.
  return verdict
end

local abort_requested = function()
  return rconn:hget(ident, 'abort_requested')
end

-- Should this result be flagged as an error?
local is_error = function(statcode, err)
  -- 5xx: yes
  if statcode >= 500 then
    return true
  end

  -- Response code zero with non-RETRFINISHED wget code: yes
  if statcode == 0 and err ~= 'RETRFINISHED' then
    return true
  end

  -- Could be an error, but we don't know it as such
  return false
end

-- Should this result be flagged as a warning?
local is_warning = function(statcode, err)
  return statcode >= 400 and statcode < 500
end

local handle_result = function(url_info, error_info, http_info)
  if http_info then
    -- Update the traffic counters.
    rconn:hincrby(ident, 'bytes_downloaded', http_info.body.content_size)
  end

  local statcode = 0
  local error = nil

  if http_info then
    statcode = http_info['status_code']
  end
  if error_info then
    error = error_info['error']
  end

  -- Record the current time, URL, response code, and wget's error code.
  local result = {
    ts = os.time(),
    url = url_info.url,
    response_code = statcode,
    wget_code = error,
    is_error = is_error(statcode, err),
    is_warning = is_warning(statcode, err),
    type = 'download'
  }

  -- Publish the log entry, and bump the log counter.
  do_log(1, ident, json.encode(result), log_channel, log_key)

  -- Update settings.
  if archivebot.update_settings(ident, rconn) then
    io.stdout:write("Settings updated: ")
    io.stdout:write(archivebot.inspect_settings())
    io.stdout:write("\n")
    io.stdout:flush()
  end

  -- Should we abort?
  if abort_requested() then
    io.stdout:write("Wget terminating on bot command\n")
    io.stdout:flush()
    do_abort(1, ident, log_channel)

    return wpull_hook.actions.STOP
  end

  -- OK, we've finished our fetch attempt.  Now we need to figure out how much
  -- we should delay.  We delay different amounts for page requisites vs.
  -- non-page requisites because browsers act that way.
  local sl, sm

  if requisite_urls[url_info.url] then
    -- Yes, this will eventually free the memory needed for the key
    requisite_urls[url_info.url] = nil

    sl, sm = archivebot.pagereq_delay_time_range()
  else
    sl, sm = archivebot.delay_time_range()
  end

  socket.sleep(math.random(sl, sm) / 1000)

  return wpull_hook.actions.NORMAL
end

wpull_hook.callbacks.handle_response = function(url_info, http_info)
  return handle_result(url_info, nil, http_info)
end

wpull_hook.callbacks.handle_error = function(url_info, error_info)
  return handle_result(url_info, error_info, nil)
end

wpull_hook.callbacks.finish_statistics = function(start_time, end_time, num_urls, bytes_downloaded)
  io.stdout:write("  ")
  io.stdout:write(bytes_downloaded.." bytes.")
  io.stdout:write("\n")
  io.stdout:flush()
end

-- vim:ts=2:sw=2:et:tw=78
