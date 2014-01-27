# Given a Lua script, creates a function for executing the script.
#
# On first invocation, this function executes a SCRIPT LOAD, and stores the
# returned SHA1 for further use via EVALSHA.  Subsequent executions will use
# EVALSHA.
#
# If an EVALSHA fails with NOSCRIPT, the SCRIPT LOAD sequence is repeated and
# the EVALSHA retried.  Other errors are passed through to the caller.
#
# The returned function has the same calling convention as redis-lua's eval.
# An example:
#
#    f = eval_redis(some_script, rconn)
#
#    # calls the script in f with one key ("foo") and two arguments ("bar",
#    # "baz")
#    f(1, 'foo', 'bar', baz')
#
# The connection object you pass in must remain connected for the lifetime of
# the generated function.  If you re-establish a Redis connection, you must
# regenerate the script function.
def eval_redis(script, rconn):
  script_sha = None

  def run_script(*args, **kwargs):
    return rconn.evalsha(script_sha, *args, **kwargs)

  # local x = function() behaves like let.  local function x() behaves more
  # like letrec.
  # Go figure.
  def helper(*args, **kwargs):
    if script_sha is None:
      script_sha = rconn.script('LOAD', script)

    ok, result = pcall(run_script, *args, **kwargs)

    if ok:
      return result
    else:
      if isinstance(result, str) and re.match('NOSCRIPT', result):
        script_sha = None
        return helper(*args, **kwargs)
      else:
        error(result)

  return helper


# vim:ts=2:sw=2:et:tw=78
