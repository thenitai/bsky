#!/bin/bash

# Detects an image in the Wayland clipboard and dumps it to a temp file.
# Converts GIF/BMP/other exotic types to PNG via ffmpeg.
#
# stdout: "<mime>\t<path>\t<size>"   exit 0 on success, 1 when no image.

set -euo pipefail

mime=""
for m in image/png image/jpeg image/webp image/gif image/bmp; do
  if wl-paste --list-types 2>/dev/null | grep -qx "$m"; then
    mime="$m"
    break
  fi
done
[ -n "$mime" ] || exit 1

tmp=$(mktemp /tmp/omarchy-bsky-clip.XXXXXX) || exit 1
if ! wl-paste --type "$mime" >"$tmp" 2>/dev/null; then
  rm -f "$tmp"
  exit 1
fi
if [ ! -s "$tmp" ]; then
  rm -f "$tmp"
  exit 1
fi

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
