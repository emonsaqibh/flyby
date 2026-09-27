#!/bin/bash
# Builds and launches the dev build. Never touches the installed release.
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
pkill -f 'Flyby Dev.app/Contents/MacOS/Flyby' 2>/dev/null || true
open "build/Flyby Dev.app"
echo "✓ Launched Flyby Dev — it lives in the menu bar."
