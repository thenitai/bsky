#!/bin/bash

# Uploads one image blob to the user's PDS via com.atproto.repo.uploadBlob.
# The access JWT is read from the session file so it never appears in argv
# or the environment; it is placed in a 0600 temp header file.
#
# Usage: upload-blob.sh <pds-url> <session.json> <mime> <image-path>
# stdout on success: the uploadBlob JSON response. stderr: "<code>|<body>".
# exit 0 on success, 1 on failure.

set -euo pipefail

pds="$1"
session_file="$2"
mime="$3"
image="$4"

jwt=$(jq -r '.accessJwt // empty' "$session_file") || jwt=""
[ -n "$jwt" ] || {
  echo "0|no session token"
  exit 1
}

hdr=$(mktemp /tmp/omarchy-bsky-hdr.XXXXXX)
resp=$(mktemp /tmp/omarchy-bsky-resp.XXXXXX)
trap 'rm -f "$hdr" "$resp"' EXIT

printf 'Authorization: Bearer %s\n' "$jwt" >"$hdr"

code=$(curl -sS -o "$resp" -w '%{http_code}' \
  -X POST "$pds/xrpc/com.atproto.repo.uploadBlob" \
  -H @"$hdr" \
  -H "Content-Type: $mime" \
  --data-binary @"$image" 2>/dev/null) || {
  echo "0|network error"
  exit 1
}

if [ "$code" = "200" ]; then
  cat "$resp"
  exit 0
fi

printf '%s|%s\n' "$code" "$(cat "$resp")" >&2
exit 1
