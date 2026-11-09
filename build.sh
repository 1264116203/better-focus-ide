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
TARGET="arm64-apple-macosx15.0"
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

# Copy app icon (CFBundleIconFile = AppIcon-NotchCard in Info.plist)
cp Resources/AppIcon-NotchCard.icns "$APP_DIR/Contents/Resources/AppIcon-NotchCard.icns"

# Copy SwiftPM resource bundles (IDE icons, etc.)
# Swift 6.4 / Xcode 27 的产物在 .build/<config>（指向 out/Products）。
# 旧布局 .build/arm64-apple-macosx/<config> 仍作兜底。缺了这个包时
# Bundle.module 会在第一次画徽章时直接把进程打崩。
RESOURCE_BUNDLE=""
for candidate in \
    ".build/$BUILD_CONFIGURATION/BetterFocusIDE_BetterFocusIDE.bundle" \
    ".build/arm64-apple-macosx/$BUILD_CONFIGURATION/BetterFocusIDE_BetterFocusIDE.bundle"
do
    if [ -d "$candidate" ]; then
        RESOURCE_BUNDLE="$candidate"
        break
    fi
done
if [ -n "$RESOURCE_BUNDLE" ]; then
    echo "▸ Copying resource bundles..."
    cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/"
fi

# 本机临时签名（ad-hoc）。不要加 --options runtime，也不要把
# com.apple.security.automation.apple-events 签进包里。
# 加固运行时加上这项受限权利后，签名只在编译这台 Mac 上有效；
# 拷到别的机器，系统直接拒绝启动，对话框是「应用程序无法打开」，右键打开也绕不过。
# 不加固运行时的非沙盒应用仍会弹出自动化授权，Apple Events 可以继续用。
# 先签资源包，再签外层。不要用 --deep，嵌套签名顺序反了会在别的机器上校验失败。
echo "▸ Signing $APP_NAME.app (ad-hoc, no hardened runtime)..."
NESTED_BUNDLE="$APP_DIR/Contents/Resources/$(basename "$RESOURCE_BUNDLE")"
if [ -n "$RESOURCE_BUNDLE" ] && [ -d "$NESTED_BUNDLE" ]; then
    codesign --force --sign - "$NESTED_BUNDLE"
fi
codesign --force --sign - "$APP_DIR"

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
