#!/bin/bash
# Download public PNG/JPEG/WebP thumbnails only; no remote image conversion.
set -euo pipefail
umask 077
tmp=$(mktemp /tmp/omarchy-bsky-card.XXXXXX)
trap 'rm -f "$tmp"' EXIT

timeout --kill-after=1 25 python3 "$(dirname "$0")/request.py" --image "$1" "$tmp" || exit 1
size=$(stat -c%s "$tmp")
[[ "$size" -gt 0 && "$size" -le 1000000 ]] || exit 1
mime=$(timeout --kill-after=1 3 file -b --mime-type "$tmp") || exit 1
case "$mime" in
  image/png | image/jpeg | image/webp) ;;
  *) exit 1 ;;
esac
printf '%s\t%s\t%s\n' "$mime" "$tmp" "$size"
trap - EXIT
