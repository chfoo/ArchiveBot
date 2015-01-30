#!/usr/bin/python3

import sys
import os
import re
import json
import difflib

from hashlib import md5
from urllib.parse import urlsplit, quote, quote_plus, unquote
from urllib.request import urlopen, HTTPError

cache_dir = "cache"


def md5_url(url):
	return md5(url.encode("utf-8")).hexdigest()


def get_cache_filename(url):
	return os.path.join(cache_dir, md5_url(url))


def get_body(url):
	fname = get_cache_filename(url)
	if os.path.exists(fname):
		with open(fname, "rb") as f:
			return f.read()
	else:
		try:
			with urlopen(url) as o:
				body = o.read()
				with open(fname, "wb") as f:
					f.write(body)
				with open(fname + ".info.json", "w") as f:
					f.write(json.dumps({"url": url}))
				return body
		except HTTPError as e:
			body = e.fp.read()
			with open(fname, "wb") as f:
				f.write(body)
			with open(fname + ".info.json", "w") as f:
				f.write(json.dumps({"url": url}))
			return body


def lower_escapes(url):
	assert isinstance(url, bytes), type(url)
	if b'%' not in url:
		return url
	return re.sub(b'(%[a-fA-F0-9]{2})', lambda m: m.group(1).lower(), url)


def kill_path(path, body):
	body = body.replace(path.encode("utf-8"), b"")
	body = body.replace(path.encode("utf-8").replace(b"/", br"\/"), b"")
	body = body.replace(quote_plus(path).encode("utf-8"), b"")
	body = body.replace(lower_escapes(quote_plus(path).encode("utf-8")), b"")
	path_without_slashes = path.replace("/", "")
	if len(path_without_slashes) >= 5:
		body = body.replace(path_without_slashes.encode("utf-8"), b"")
	# For Dokuwiki
	path_underscored = path.replace("/", "_")
	body = body.replace(path_underscored.encode("utf-8"), b"")
	# For Drupal "jQuery.extend(Drupal.settings" line
	path_jsoned = '"' + path.replace("/", "\\u002F") + '"'
	body = body.replace(path_jsoned.encode("utf-8"), b"")
	if '%' in path:
		unquoted_path = unquote(path)
		if len(unquoted_path) >= 4:
			body = body.replace(quote_plus(unquoted_path).encode("utf-8"), b"")
			body = body.replace(lower_escapes(quote_plus(unquoted_path).encode("utf-8")), b"")
	return body


def process_body(body, url):
	"""
	Return a post-processed page body that excludes irrelevant content
	that would prevent duplicate pages from being detected as duplicates.
	"""
	assert isinstance(body, bytes), type(body)

	drupal = b"Drupal" in body

	u = urlsplit(url)
	# Needed for www.tragnarion.com
	path = u.path.rstrip('/')
	if path.startswith('/'):
		path = path[1:]
	if len(path) >= 5:
		body = kill_path(path, body)
	if len(u.query) >= 3:
		encoded_query = u.query.encode("utf-8")
		body = body.replace(('?' + u.query).encode("utf-8"), b"")
		body = body.replace(quote('?' + u.query).encode("utf-8"), b"")

	# Strip HTML comments, which sometimes include timestamps or
	# page generation stats
	body = re.sub(br'<\!--.{1,4000}?-->', b"", body, count=1000, flags=re.DOTALL)

	# Drupal generates a "theme_token":"..." inside a JSON blob
	# CloudFlare has a petok:"-1413059798-86400"
	body = re.sub(br'(petok|_token|applicationTime)"?:("[-_A-Za-z0-9\.]+"|[0-9\.]+)', b"", body)

	# Handle any 10-256 characters of hex or decimal
	# Minimum of 10 to handle UNIX timestamps
	body = re.sub(br'\b[A-Fa-f0-9\.]{10,256}', b"", body)

	# Randomized anti-spam mailto: lines
	body = re.sub(br'<a href="mailto:[^"@]{1,100}@[^"]{2,100}">(&#[0-9a-fA-Fx]{2,4};){3,100}</a>', b"", body)

	# Kill twitter and facebook share buttons, no matter what kind of
	# URL they stuffed in there.
	body = re.sub(br'<div class="fb-like" data-href=".*?</div>', b"", body)
	body = re.sub(br'<a href="https?://twitter.com/share" class="twitter-share-button" data-text=".*?</a>', b"", body)

	# Drupal puts the current URL here, and the casing doesn't always match
	body = re.sub(br'<(link rel="(canonical|shortlink|alternate)".{1,1000}?href=|meta property="og:url" content=)"[^"]+" />', b"", body)

	# Spotted on http://2045.com/
	body = re.sub(br'<input type="hidden" name="file_uploadToken" value="\d+"', b"", body)

	# Spotted on http://www.museodelvideojuego.com/ - handles
	# <input type="hidden" name="form_build_id" value="form-ddmhsyCMnpZsHKCQN-l6R1j9EwMT3lHKDI4xXcyFcBA" />
	body = re.sub(br'<input type="hidden"[^>]{1,1000}?>', b"", body)

	# Spotted on http://www.communauteanimalcrossing.fr/
	body = re.sub(br'<param name="flashvars" value="servannee=\d{4}&amp;servmois=\d{1,2}&amp;servjour=\d{1,2}&amp;servheure=\d{1,2}&amp;servminute=\d{1,2}&amp;servseconde=\d{1,2}" />', b"", body)

	# Drupal generates <body class="..."> items based on the URL
	# Generated class="" also spotted on non-Drupal www.minutouno.com
	body = re.sub(br'<body class="[^"]+"', b"", body)

	# vbulletin
	body = re.sub(br'\(\d+ Viewing\)', b"", body)
	body = re.sub(br'Currently Active Users</a>: \d+ \(\d+ members and \d+ guests\)', b"", body)

	# Spotted on http://vstreamers.com/v/images/css/p/videos
	body = re.sub(br'[&\?]v=\d+', b"", body)

	if drupal:
		# Kill entire Drupal settings line
		body = re.sub(br'jQuery\.extend\(Drupal.settings, ?\{.{1,20000}?\}\);', b"", body)

		# Drupal generates this class id
		body = re.sub(br"\bview-dom-id-[0-9a-f]+\b", b"", body)

		# Drupal sites have randomized sidebar content with these IDs
		body = re.sub(br'<div class="views-field views-field-[-a-z]+">.*', b"", body)

		# nsslabs.com has this
		body = re.sub(br'<div class="breadcrumb">.{1,4000}?    </div>', b"", body)

	return body


def compare_bodies(body1, body2, url1, url2):
	# TODO: handle non-utf-8 bodies
	for line in difflib.unified_diff(
		body1.decode("utf-8", "replace").splitlines(keepends=True),
		body2.decode("utf-8", "replace").splitlines(keepends=True),
		fromfile=url1,
		tofile=url2):
		if not "\n" in line:
			line += "\n"
		sys.stdout.write(line)


def compare_unprocessed_bodies(up_body1, up_body2, url1, url2):
	body1 = process_body(up_body1, url1)
	body2 = process_body(up_body2, url2)
	print("{} == md5({!r})".format(md5_url(url1), url1))
	print("{} == md5({!r})".format(md5_url(url2), url2))
	print("After processing,")
	print("len(body({!r})) == {}".format(url1, len(body1)))
	print("len(body({!r})) == {}".format(url2, len(body2)))
	compare_bodies(body1, body2, url1, url2)


def main():
	try:
		os.makedirs(cache_dir)
	except OSError:
		pass

	assert os.path.exists(cache_dir)

	if len(sys.argv) == 2:
		# Just save and print the body
		print(get_body(sys.argv[1]))
	elif len(sys.argv) == 3:
		url1, url2 = sys.argv[1], sys.argv[2]
		compare_unprocessed_bodies(get_body(url1), get_body(url2), url1, url2)
	else:
		assert 0, sys.argv


if __name__ == '__main__':
	main()
