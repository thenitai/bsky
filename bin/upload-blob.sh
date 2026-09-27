#!/bin/bash

# Uploads one image blob to the user's PDS via com.atproto.repo.uploadBlob.
# The access JWT is read from the session file so it never appears in argv
# or the environment; it is placed in a 0600 temp header file.
#
# Usage: upload-blob.sh <pds-url> <session.json> <mime> <image-path>
# stdout on success: the uploadBlob JSON response. stderr: "<code>|<body>".
# exit 0 on success, 1 on failure.

set -euo pipefail

readonly CONNECT_TIMEOUT_SECONDS=10
readonly TOTAL_TIMEOUT_SECONDS=30
readonly MAX_RESPONSE_BYTES=262144
readonly MAX_RESPONSE_BLOCKS=$(((MAX_RESPONSE_BYTES + 1023) / 1024))

pds="$1"
session_file="$2"
mime="$3"
image="$4"

[[ "$pds" == https://* ]] || {
  printf '%s\n' "0|PDS URL must use HTTPS" >&2
  exit 1
}

jwt=$(jq -r '.accessJwt // empty' "$session_file") || jwt=""
[ -n "$jwt" ] || {
  echo "0|no session token"
  exit 1
}

hdr=$(mktemp /tmp/omarchy-bsky-hdr.XXXXXX)
resp=$(mktemp /tmp/omarchy-bsky-resp.XXXXXX)
trap 'rm -f "$hdr" "$resp"' EXIT
ulimit -c 0
ulimit -f "$MAX_RESPONSE_BLOCKS"

printf 'Authorization: Bearer %s\n' "$jwt" >"$hdr"

if code=$(curl --disable --proto '=https' --proto-redir '=https' -sS --connect-timeout "$CONNECT_TIMEOUT_SECONDS" --max-time "$TOTAL_TIMEOUT_SECONDS" --max-filesize "$MAX_RESPONSE_BYTES" -o "$resp" -w '%{http_code}' -X POST "$pds/xrpc/com.atproto.repo.uploadBlob" -H @"$hdr" -H "Content-Type: $mime" --data-binary @"$image" 2>/dev/null); then
  :
else
  curl_status=$?
  if [[ "$curl_status" == "63" || "$curl_status" == "153" ]]; then
    printf '0|Bluesky upload response exceeded %s bytes\n' "$MAX_RESPONSE_BYTES" >&2
    exit 1
  fi
  echo "0|network error"
  exit 1
fi

response_size=$(stat -c%s "$resp")
if ((response_size > MAX_RESPONSE_BYTES)); then
  printf '0|Bluesky upload response exceeded %s bytes\n' "$MAX_RESPONSE_BYTES" >&2
  exit 1
fi

if [ "$code" = "200" ]; then
  cat "$resp"
  exit 0
fi

printf '%s|%s\n' "$code" "$(cat "$resp")" >&2
exit 1
