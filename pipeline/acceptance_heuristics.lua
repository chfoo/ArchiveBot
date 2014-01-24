-- Is this a URL of a non-hyperlinked page requisite?
is_page_requisite = function(record_info)
  local is_requisite = record_info['inline']

  return record_info['link_type'] ~= 'html' and is_requisite == 1
end

-- Given two URLs A and B, determines whether a link between A and B is
--
-- 1. a www.DOMAIN -> DOMAIN transition or a DOMAIN -> www.DOMAIN transition
-- 2. whether A's path is a subpath of B
--
-- These days, bare domains are very commonly an alias for www (actually, it
-- might be more correct to state that the other way around).  Therefore we
-- should crawl links like
--
-- http://www.example.com/foo -> http://example.com/foo/bar (it's a child)
-- http://example.com/foo -> http://www.example.com/foo (same path level)
--
-- but not links like
--
-- http://www.example.com/foo -> http://example.com/baz (different path)
-- http://example.com/bar -> http://ugh.example.com/bar (different domain)
--
-- This is a rather odd heuristic, but so are bare domains.
--
-- url_a and url_b must be tables containing the keys "url" and "path".  The
-- url key must contain an absolute URL; the path key must contain an absolute
-- path component.
is_www_to_bare = function(parent, child)
  local www_to_bare_p = function(host_a, host_b)
    local bare_domain = string.match(host_a, '^www.([^.]+.[^.]+)$')

    return host_b == bare_domain
  end

  -- Is the parent a www.example.com and the child an example.com, or vice
  -- versa?
  local p_to_bare = www_to_bare_p(parent.hostname, child.hostname)
  local bare_to_p = www_to_bare_p(child.hostname, parent.hostname)

  -- Is the parent's path a subpath of the child's path?
  local start = string.find(child.path, parent.path, 1, true)
  local is_subpath = (start == 1)

  return (p_to_bare or bare_to_p) and is_subpath
end

is_span_host_filter_failed_only = function(filter_statuses)
  for name, passed in pairs(filter_statuses) do
    if not passed and name ~= 'SpanHostsFilter' then
      return false
    end
  end

  return filter_statuses['SpanHostsFilter'] == false
end

-- vim:ts=2:sw=2:et:tw=78
