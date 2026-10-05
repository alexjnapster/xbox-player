#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
case "${1:-}" in
  ""|--install) ;;
  *) echo "Usage: $0 [--install]" >&2; exit 2 ;;
esac
stage="$(mktemp -d "${TMPDIR:-/tmp}/xbox-player-build.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/Xbox Player.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$root/build"
cp -X "$root/Resources/Info.plist" "$app/Contents/Info.plist"
cp -X "$root/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
xcrun swiftc -swift-version 5 -O -framework Cocoa -framework AVFoundation -framework MetalKit \
  "$root/Sources/ModePolicy.swift" "$root/Sources/main.swift" -o "$app/Contents/MacOS/Xbox Player"
xattr -cr "$app"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
# ZIP is built from the signed staging bundle, not a Finder-managed output folder.
ditto -c -k --keepParent --norsrc "$app" "$root/build/Xbox Player.zip"
ditto --norsrc "$app" "$root/build/Xbox Player.app"
if [ "${1:-}" = --install ]; then
  if pgrep -f '^/Applications/Xbox Player.app/Contents/MacOS/Xbox Player' >/dev/null; then
    echo 'Quit the running Xbox Player before installation.' >&2; exit 1
  fi
  ditto --norsrc "$app" '/Applications/Xbox Player.app'
  xattr -cr '/Applications/Xbox Player.app'
  codesign --verify --strict '/Applications/Xbox Player.app'
fi
printf 'Built %s\n' "$root/build/Xbox Player.app"
