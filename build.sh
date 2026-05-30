#!/bin/bash
# 编译并打包 QuickTranslate.app
set -e
ROOT="$HOME/quicktranslate"
APP="$ROOT/build/QuickTranslate.app"
BIN="$APP/Contents/MacOS/QuickTranslate"

echo "==> 清理旧 bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> 编译 (arm64, macOS 12+)"
xcrun -sdk macosx swiftc -O \
  -target arm64-apple-macos12.0 \
  -framework AppKit -framework Carbon -framework Vision \
  "$ROOT/src/main.swift" -o "$BIN"

echo "==> 写 Info.plist (LSUIElement 后台运行)"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>QuickTranslate</string>
  <key>CFBundleDisplayName</key><string>QuickTranslate</string>
  <key>CFBundleIdentifier</key><string>com.local.quicktranslate</string>
  <key>CFBundleVersion</key><string>1.0.0</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleExecutable</key><string>QuickTranslate</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>用于调用系统翻译快捷指令</string>
</dict>
</plist>
PLIST

echo "==> ad-hoc 签名 (稳定权限授权)"
codesign --force --deep -s - "$APP" 2>/dev/null || true

echo "==> 完成: $APP"
