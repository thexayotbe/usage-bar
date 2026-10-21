#!/bin/bash
# Remove the app. Pass --purge to also delete its config and cache.
set -euo pipefail
pkill -x Usage 2>/dev/null || true
rm -rf "$HOME/Applications/Usage.app"
if [ "${1:-}" = "--purge" ]; then
  rm -rf "$HOME/.config/usage-bar" "$HOME/Library/Caches/dev.thexayotbe.usage"
  echo "Removed the app, its config and its cache."
else
  echo "Removed the app. Config (~/.config/usage-bar) and cache are kept; use --purge to delete them."
fi
echo "If you enabled 'Launch at login', also remove Usage in System Settings → General → Login Items."
