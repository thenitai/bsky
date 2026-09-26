#!/bin/bash
# Bound clipboard offers on disk before exposing text or image metadata to QML.
set -euo pipefail
umask 077
ulimit -c 0
tmp=$(mktemp /tmp/omarchy-bsky-clip.XXXXXX)
out="${tmp}.png"
trap 'rm -f "$tmp" "$out"' EXIT

if [[ "${1:-}" == text ]]; then
  ulimit -S -f 64
  timeout --kill-after=1 5 wl-paste --type text >"$tmp" 2>/dev/null || exit 1
  [[ $(stat -c%s "$tmp") -le 65536 ]] || exit 1
  cat "$tmp"
  exit 0
fi

# Bound type enumeration too; never buffer an untrusted offer list in the shell.
ulimit -S -f 64
timeout --kill-after=1 5 wl-paste --list-types >"$tmp" 2>/dev/null || exit 1
mime=""
for m in image/png image/jpeg image/webp image/gif image/bmp; do
  if grep -qx "$m" "$tmp"; then
    mime="$m"
    break
  fi
done
[[ -n "$mime" ]] || exit 1
# The soft limit can be raised up to the inherited hard limit.
ulimit -S -f 977
timeout --kill-after=1 5 wl-paste --type "$mime" >"$tmp" 2>/dev/null || exit 1
size=$(stat -c%s "$tmp")
[[ "$size" -gt 0 && "$size" -le 1000000 ]] || exit 1
case "$mime" in
  image/png | image/jpeg | image/webp) ;;
  *)
    timeout --kill-after=1 10 ffmpeg -y -loglevel error -max_alloc 16777216 -i "$tmp" -frames:v 1 "$out" >/dev/null 2>&1 || exit 1
    [[ -s "$out" ]] || exit 1
    mv "$out" "$tmp"
    mime="image/png"
    ;;
esac
size=$(stat -c%s "$tmp")
[[ "$size" -le 1000000 ]] || exit 1
hash=$(sha256sum "$tmp" | awk '{print $1}')
printf '%s\t%s\t%s\t%s\n' "$mime" "$tmp" "$size" "$hash"
trap - EXIT
