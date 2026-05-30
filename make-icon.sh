#!/bin/bash
# 从 assets/logo-mark.svg 生成 assets/AppIcon.icns
set -euo pipefail
ROOT="$HOME/quicktranslate"
SVG="$ROOT/assets/logo-mark.svg"
WORK="$(mktemp -d)"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

echo "==> 渲染 SVG -> 1024 PNG"
qlmanage -t -s 1024 -o "$WORK" "$SVG" >/dev/null 2>&1
MASTER="$WORK/$(basename "$SVG").png"
[ -f "$MASTER" ] || { echo "渲染失败"; exit 1; }

echo "==> 生成各尺寸"
gen() { sips -z "$2" "$2" "$MASTER" --out "$ICONSET/icon_$1.png" >/dev/null 2>&1; }
gen 16x16        16
gen 16x16@2x     32
gen 32x32        32
gen 32x32@2x     64
gen 128x128     128
gen 128x128@2x  256
gen 256x256     256
gen 256x256@2x  512
gen 512x512     512
gen 512x512@2x 1024

echo "==> 合成 icns"
iconutil -c icns "$ICONSET" -o "$ROOT/assets/AppIcon.icns"
rm -rf "$WORK"
echo "==> 完成: assets/AppIcon.icns ($(stat -f%z "$ROOT/assets/AppIcon.icns") bytes)"
