#!/bin/bash
# Build build/Usage.app (ad-hoc signed). Needs Xcode Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")/app"
swift build -c release
APP="../build/Usage.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Usage "$APP/Contents/MacOS/Usage"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null
echo "Built $(cd .. && pwd)/build/Usage.app"
