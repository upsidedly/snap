#!/bin/zsh
set -euo pipefail
PROJECT_DIR=${0:A:h:h}
cd "$PROJECT_DIR"
if [[ -z ${DEVELOPER_DIR:-} && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
xcrun swift build -c release
SNAP_BIN_DIR=$(xcrun swift build -c release --show-bin-path)
APP_DIR="$PROJECT_DIR/build/Snap.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$SNAP_BIN_DIR/Snap" "$APP_DIR/Contents/MacOS/Snap"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
xcrun swiftc Sources/Snap/SnapIcon.swift scripts/make-icon.swift -o build/make-icon
build/make-icon "$PROJECT_DIR/build"
cp build/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
plutil -lint "$APP_DIR/Contents/Info.plist"
"$PROJECT_DIR/scripts/sign.sh" "$APP_DIR"
print "Built $APP_DIR"
