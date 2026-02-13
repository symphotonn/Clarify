#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Building..."
xcodebuild -project Clarify.xcodeproj -scheme Clarify -destination 'platform=macOS' build -quiet

BUILD_DIR=$(xcodebuild -project Clarify.xcodeproj -scheme Clarify -showBuildSettings 2>/dev/null \
  | grep -m1 'BUILT_PRODUCTS_DIR' | awk '{print $3}')

TARGET=~/Applications/Clarify.app

# Kill running instance
pkill -x Clarify 2>/dev/null || true
sleep 0.3

# Sync in-place to preserve macOS permission grants (rsync avoids deleting the .app)
mkdir -p ~/Applications
rsync -a --delete "$BUILD_DIR/Clarify.app/" "$TARGET/"

echo "Launching ~/Applications/Clarify.app"
open "$TARGET"
