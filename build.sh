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

echo "==> 拷贝图标资源"
[ -f "$ROOT/assets/AppIcon.icns" ] || bash "$ROOT/make-icon.sh" || true
[ -f "$ROOT/assets/AppIcon.icns" ] && cp "$ROOT/assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns" || echo "   (无 app 图标)"
[ -f "$ROOT/assets/menubar.png" ] && cp "$ROOT/assets/menubar.png" "$APP/Contents/Resources/menubar.png" || echo "   (无菜单栏图标, 回退为「译」)"

echo "==> 写 Info.plist (LSUIElement 后台运行)"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>QuickTranslate</string>
  <key>CFBundleDisplayName</key><string>QuickTranslate</string>
  <key>CFBundleIdentifier</key><string>com.local.quicktranslate</string>
  <key>CFBundleVersion</key><string>1.1.0</string>
  <key>CFBundleShortVersionString</key><string>1.1.0</string>
  <key>CFBundleExecutable</key><string>QuickTranslate</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>用于调用系统翻译快捷指令</string>
</dict>
</plist>
PLIST

echo "==> 代码签名"
# 优先用稳定的自签名证书：授权依据基于证书而非 cdhash，重编译/重装后辅助功能授权不失效。
# 一次性创建：见 README「稳定签名（可选）」。没有证书则回退 ad-hoc。
IDENTITY="QuickTranslate Local Signing"
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  codesign --force --deep -s "$IDENTITY" "$APP" 2>/dev/null && echo "   ✓ 稳定证书签名 ($IDENTITY)"
else
  codesign --force --deep -s - "$APP" 2>/dev/null && echo "   ad-hoc 签名（建议创建稳定证书，见 README）"
fi

echo "==> 完成: $APP"
