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

# 菜单栏单色模板：menubar.svg(黑字白底) -> 亮度反转为透明 alpha
if [ -f "$ROOT/assets/menubar.svg" ]; then
  echo "==> 生成菜单栏模板 menubar.png"
  qlmanage -t -s 144 -o "$WORK" "$ROOT/assets/menubar.svg" >/dev/null 2>&1
  SWIFT_SRC="$WORK/lum2alpha.swift"
  cat > "$SWIFT_SRC" <<'SW'
import AppKit
let inP = CommandLine.arguments[1], outP = CommandLine.arguments[2]
guard let img = NSImage(contentsOfFile: inP), let tiff = img.tiffRepresentation,
      let src = NSBitmapImageRep(data: tiff) else { fatalError("load") }
let w = src.pixelsWide, h = src.pixelsHigh
let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: w*4, bitsPerPixel: 32)!
for y in 0..<h { for x in 0..<w {
    let c = src.colorAt(x: x, y: y)!
    let lum = c.redComponent*0.299 + c.greenComponent*0.587 + c.blueComponent*0.114
    out.setColor(NSColor(deviceRed: 0, green: 0, blue: 0, alpha: (1.0-lum)*c.alphaComponent), atX: x, y: y)
}}
try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outP))
SW
  xcrun -sdk macosx swiftc "$SWIFT_SRC" -o "$WORK/lum2alpha" 2>/dev/null \
    && "$WORK/lum2alpha" "$WORK/menubar.svg.png" "$ROOT/assets/menubar.png"
fi

rm -rf "$WORK"
echo "==> 完成: assets/AppIcon.icns + assets/menubar.png"
