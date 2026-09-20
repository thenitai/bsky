#!/bin/bash

# Refreshes an AT Protocol session without putting the refresh JWT in argv or
# the environment. The endpoint accepts no request body.

set -euo pipefail

readonly CONNECT_TIMEOUT_SECONDS=10
readonly TOTAL_TIMEOUT_SECONDS=30
readonly MAX_RESPONSE_BYTES=262144
readonly MAX_RESPONSE_BLOCKS=$(((MAX_RESPONSE_BYTES + 1023) / 1024))

session_file="$1"
pds="${2%/}"
header_file=$(mktemp)
body_file=$(mktemp)
trap 'rm -f "$header_file" "$body_file"' EXIT
ulimit -c 0
ulimit -f "$MAX_RESPONSE_BLOCKS"

refresh_jwt=$(jq -er '.refreshJwt | select(type == "string" and length > 0)' "$session_file")
umask 077
printf 'Authorization: Bearer %s\n' "$refresh_jwt" > "$header_file"
chmod 600 "$header_file"

if http_code=$(curl --silent --show-error --connect-timeout "$CONNECT_TIMEOUT_SECONDS" --max-time "$TOTAL_TIMEOUT_SECONDS" --max-filesize "$MAX_RESPONSE_BYTES" --output "$body_file" --write-out '%{http_code}' --request POST --header "@$header_file" "$pds/xrpc/com.atproto.server.refreshSession"); then
  :
else
  curl_status=$?
  if [[ "$curl_status" == "63" || "$curl_status" == "153" ]]; then
    printf '0||Bluesky session response exceeded %s bytes\n' "$MAX_RESPONSE_BYTES" >&2
    exit 1
  fi
  printf '0||Network error while refreshing the Bluesky session\n' >&2
  exit 1
fi

body_size=$(stat -c%s "$body_file")
if ((body_size > MAX_RESPONSE_BYTES)); then
  printf '0||Bluesky session response exceeded %s bytes\n' "$MAX_RESPONSE_BYTES" >&2
  exit 1
fi

if [[ "$http_code" == "200" ]]; then
  cat "$body_file"
  exit 0
fi

error_code=$(jq -r '.error // ""' "$body_file" 2>/dev/null || true)
message=$(jq -r '.message // .error // "Session refresh failed"' "$body_file" 2>/dev/null || true)
printf '%s|%s|%s\n' "$http_code" "$error_code" "${message:-Session refresh failed}" >&2
exit 1
