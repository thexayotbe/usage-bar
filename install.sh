#!/bin/bash
# Build, copy to ~/Applications and launch.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v swift >/dev/null 2>&1; then
  echo "swift not found. Install the Xcode Command Line Tools first:  xcode-select --install" >&2
  exit 1
fi

./build.sh
mkdir -p "$HOME/Applications"
pkill -x Usage 2>/dev/null || true
rm -rf "$HOME/Applications/Usage.app"
cp -R build/Usage.app "$HOME/Applications/Usage.app"
open "$HOME/Applications/Usage.app"
echo "Installed ~/Applications/Usage.app — look for the ring in your menu bar."
echo "Config: ~/.config/usage-bar/config.json (created on first run)"
