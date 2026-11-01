#!/bin/bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$APP_DIR/build"
APP_BUNDLE="$APP_DIR/OrcaMirror.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "Building OrcaMirror native macOS app..."

mkdir -p "$BUILD_DIR"
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

# Compile Swift sources into ARM64 native binary
swiftc -O \
    -target arm64-apple-macos14.0 \
    -framework Cocoa \
    -framework AVFoundation \
    -framework AudioToolbox \
    -framework CoreMediaIO \
    -framework CoreMedia \
    -framework CoreVideo \
    -framework CoreImage \
    -o "$MACOS/OrcaMirror" \
    "$APP_DIR/Sources/DeviceManager.swift" \
    "$APP_DIR/Sources/LowLatencyAudioPlayer.swift" \
    "$APP_DIR/Sources/ColorProfileManager.swift" \
    "$APP_DIR/Sources/CaptureController.swift" \
    "$APP_DIR/Sources/ControlsWindowController.swift" \
    "$APP_DIR/Sources/MirrorViewController.swift" \
    "$APP_DIR/Sources/MirrorWindowController.swift" \
    "$APP_DIR/Sources/AppDelegate.swift" \
    "$APP_DIR/Sources/main.swift"

# Copy Info.plist and Icon
cp "$APP_DIR/Resources/Info.plist" "$CONTENTS/Info.plist"
if [ -f "$APP_DIR/Resources/AppIcon.icns" ]; then
    cp "$APP_DIR/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
fi

# Codesign ad-hoc
codesign --force --deep -s - "$APP_BUNDLE"

echo "Build successful: $APP_BUNDLE"
