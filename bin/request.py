#!/usr/bin/env python3
"""Bound HTTP input before it enters Quickshell; request secrets arrive on stdin."""
import json
import sys
import signal
import urllib.request

MAX_BYTES = 262144
# Process-wide deadline also covers slow response headers and trickle streams.
signal.alarm(30)
try:
    options = json.load(sys.stdin)
    if not options['url'].startswith(('https://', 'http://')):
        raise ValueError('Unsupported URL')
    # Return all status bodies directly; never forward credentials on redirects.
    status_handler = urllib.request.HTTPErrorProcessor()
    status_handler.http_response = status_handler.https_response = lambda request, response: response
    opener = urllib.request.build_opener(status_handler)
    body = options.get('body')
    request = urllib.request.Request(options['url'], data=body.encode('utf-8') if body is not None else None, headers=options.get('headers', {}), method=options.get('method', 'GET'))
    with opener.open(request, timeout=10) as response:
        # read(n) has a hard bound even for chunked, missing/lying Content-Length,
        # and error responses. One sentinel byte detects overflow before decoding.
        data = response.read(MAX_BYTES + 1)
        if len(data) > MAX_BYTES:
            raise ValueError('HTTP response exceeded 262144 bytes')
        result = {'status': response.status, 'text': data.decode('utf-8', errors='replace')}
except Exception as error:
    result = {'status': 0, 'text': '', 'error': 'HTTP response exceeded 262144 bytes' if isinstance(error, ValueError) and str(error).startswith('HTTP response exceeded') else 'Network request failed'}
print(json.dumps(result))
