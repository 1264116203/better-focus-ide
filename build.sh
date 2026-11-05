#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 BetterFocusIDE

# Builds BetterFocusIDE, assembles the .app bundle, and signs it.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="BetterFocusIDE"
EXECUTABLE="BetterFocusIDEApp"
APP_BUNDLE_ID="com.betterfocus.ide"
BUILD_CONFIGURATION="debug"
TARGET="arm64-apple-macosx14.0"
ENTITLEMENTS="Resources/BetterFocusIDE.entitlements"

# Clean previous build
echo "▸ Cleaning previous build..."
rm -rf .build/$BUILD_CONFIGURATION/$APP_NAME.app
rm -rf .build/$BUILD_CONFIGURATION/$EXECUTABLE

# Build with Swift Package Manager
# --disable-sandbox：本机环境下 SwiftPM 的 sandbox-exec 会报
# `sandbox_apply: Operation not permitted`，与代码无关，必须关沙箱才能构建。
echo "▸ Building $APP_NAME..."
swift build -c $BUILD_CONFIGURATION --disable-sandbox

# Create .app bundle structure
echo "▸ Assembling .app bundle..."
APP_DIR=".build/$BUILD_CONFIGURATION/$APP_NAME.app"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy executable
cp .build/$BUILD_CONFIGURATION/$EXECUTABLE "$APP_DIR/Contents/MacOS/$EXECUTABLE"

# Copy Info.plist
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"

# Copy entitlements (for reference, not used in ad-hoc signing)
cp "$ENTITLEMENTS" "$APP_DIR/Contents/Resources/"

# Copy SwiftPM resource bundles (IDE icons, etc.)
RESOURCE_BUNDLE=".build/arm64-apple-macosx/$BUILD_CONFIGURATION/BetterFocusIDE_BetterFocusIDE.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    echo "▸ Copying resource bundles..."
    cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/"
fi

# Sign the app (ad-hoc with hardened runtime for more stable TCC permissions)
echo "▸ Signing $APP_NAME.app (ad-hoc with hardened runtime)..."
codesign --force --deep --sign - --options=runtime --entitlements "$ENTITLEMENTS" "$APP_DIR"

# Clear quarantine attribute to reduce permission prompts
echo "▸ Clearing quarantine attribute..."
xattr -dr com.apple.quarantine "$APP_DIR" 2>/dev/null || true

echo "✓ Build complete: $APP_DIR"
echo ""
echo "To run:"
echo "  open $APP_DIR"
echo ""
echo "To install to /Applications:"
echo "  cp -R $APP_DIR /Applications/"
echo ""
echo "Note: If macOS still shows security prompt, run:"
echo "  sudo xattr -dr com.apple.quarantine /Applications/$APP_NAME.app"
