# Runtime settings.  These are updated every time httploop_result is called.
settings = dict(
  age = None,
  ignore_patterns = {},
  delay_min = None,
  delay_max = None,
  pagereq_delay_min = None,
  pagereq_delay_max = None
)

# If updated settings exist, updates all settings and returns true.
# Otherwise, leaves settings unchanged and returns false.
def update_settings(ident, rconn):
  age = rconn.hget(ident, 'settings_age')

  if age != settings['age']:
    results = rconn.hmget(ident,
      'delay_min', 'delay_max', 'pagereq_delay_min', 'pagereq_delay_max',
      'ignore_patterns_set_key')

    settings['delay_min'] = results[1]
    settings['delay_max'] = results[2]
    settings['pagereq_delay_min'] = results[3]
    settings['pagereq_delay_max'] = results[4]
    settings['ignore_patterns'] = rconn.smembers(results[5])
    settings['age'] = age
    return True
  else:
    return False


# If a URL matches an ignore pattern, returns the matching pattern.
# Otherwise, returns false.
def ignore_url_p(url):
  for i, pattern in settings['ignore_patterns'].items():
   if re.search(pattern, url):
     return pattern

  return False

# Returns a range of valid sleep times.  Sleep times are in milliseconds.
def delay_time_range():
  return settings['delay_min'] or 0, settings['delay_max'] or 0


# Returns a range of valid sleep times for page requisites.  Sleep times are
# in milliseconds.
def pagereq_delay_time_range():
  return settings['pagereq_delay_min'] or 0, settings['pagereq_delay_max'] or 0


# Returns a string describing the current settings.
def inspect_settings():
  iglen = len(settings['ignore_patterns'])
  sl, sm = delay_time_range()
  rsl, rsm = pagereq_delay_time_range()

  report = '' + iglen + ' ignore patterns, '
  report += 'delay min/max: [' + sl + ', ' + sm + '] ms, '
  report += 'pagereq delay min/max: [' + rsl + ', ' + rsm + '] ms'

  return report

# vim:ts=2:sw=2:et:tw=78
