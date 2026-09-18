#!/bin/bash

# Downloads a remote image (e.g. og:image for a link card) to a temp file and
# converts it to an embed-allowed mime type via ffmpeg when needed.
#
# Usage: fetch-image.sh <url>
# stdout: "<mime>\t<path>\t<size>"   exit 1 on failure.

set -euo pipefail

url="$1"
tmp=$(mktemp /tmp/omarchy-bsky-card.XXXXXX) || exit 1

if ! curl -sSL --max-time 20 --max-filesize 2000000 -o "$tmp" "$url" 2>/dev/null; then
  rm -f "$tmp"
  exit 1
fi
if [ ! -s "$tmp" ]; then
  rm -f "$tmp"
  exit 1
fi

mime=$(file -b --mime-type "$tmp" 2>/dev/null || echo "application/octet-stream")

case "$mime" in
  image/png | image/jpeg | image/webp) ;;
  *)
    out="${tmp}.png"
    if command -v ffmpeg >/dev/null 2>&1 &&
      ffmpeg -y -loglevel error -i "$tmp" "$out" >/dev/null 2>&1 &&
      [ -s "$out" ]; then
      rm -f "$tmp"
      tmp="$out"
      mime="image/png"
    else
      rm -f "$tmp"
      exit 1
    fi
    ;;
esac

size=$(stat -c%s "$tmp")
printf '%s\t%s\t%s\n' "$mime" "$tmp" "$size"
