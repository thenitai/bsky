#!/usr/bin/env python3
"""Bound HTTP input before it enters Quickshell; request secrets arrive on stdin."""
import json
import ipaddress
import resource
import socket
import subprocess
import sys
import signal
import urllib.request

MAX_BYTES = 262144
# Process-wide deadline also covers slow response headers and trickle streams.
signal.alarm(30)
# Thumbnail mode pins validated DNS results so curl cannot resolve a different
# address later. No redirects, proxies, user curl configuration or conversion.
if len(sys.argv) == 4 and sys.argv[1] == '--image':
    try:
        target = urllib.parse.urlsplit(sys.argv[2])
        if target.scheme not in ('http', 'https') or not target.hostname or target.username is not None or target.password is not None:
            raise ValueError('Unsupported thumbnail URL')
        host = target.hostname.encode('idna').decode('ascii')
        port = target.port or (443 if target.scheme == 'https' else 80)
        addresses = [ipaddress.ip_address(entry[4][0]) for entry in socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)]
        if not addresses or any(not ip.is_global or ip.is_multicast or ip.is_reserved or (ip.version == 6 and (ip not in ipaddress.ip_network('2000::/3') or ip.sixtofour or ip.teredo)) for ip in addresses):
            raise ValueError('Thumbnail address is not public')
        address = str(addresses[0])
        pinned = '[' + address + ']' if addresses[0].version == 6 else address
        authority = '[' + host + ']' if ':' in host else host
        url = urllib.parse.urlunsplit((target.scheme, authority + ':' + str(port), target.path, target.query, ''))
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
        resource.setrlimit(resource.RLIMIT_FSIZE, (1000000, 1000000))
        result = subprocess.run(['curl', '--disable', '--silent', '--fail', '--proxy', '', '--noproxy', '*', '--proto', '=http,https', '--connect-timeout', '5', '--max-time', '20', '--max-filesize', '1000000', '--resolve', host + ':' + str(port) + ':' + pinned, '--output', sys.argv[3], '--write-out', '%{http_code}', '--url', url], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=21, check=True)
        if result.stdout != b'200':
            raise ValueError('Thumbnail response was not successful')
    except Exception:
        sys.exit(1)
    sys.exit(0)

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
