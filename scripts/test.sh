#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
"$root/scripts/build.sh"
exe="$root/build/Xbox Player.app/Contents/MacOS/Xbox Player"
"$exe" --test-modes
"$exe" --test-render
