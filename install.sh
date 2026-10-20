#!/bin/bash
# Build, copy to ~/Applications and launch.
set -euo pipefail
cd "$(dirname "$0")"

CTL="$HOME/.claude-control/bin/ctl.py"
if [ ! -f "$CTL" ]; then
  echo "Missing $CTL — the Usage app reads the limits that 'ctl.py quota' writes. See README → Requirements." >&2
  exit 1
fi
if ! python3 "$CTL" quota --cached >/dev/null 2>&1; then
  echo "Your ctl.py has no 'quota' command yet. See README → Requirements." >&2
  exit 1
fi

./build.sh
mkdir -p "$HOME/Applications"
pkill -x Usage 2>/dev/null || true
rm -rf "$HOME/Applications/Usage.app"
cp -R build/Usage.app "$HOME/Applications/Usage.app"
open "$HOME/Applications/Usage.app"
echo "Installed ~/Applications/Usage.app — look for the ring in your menu bar."
