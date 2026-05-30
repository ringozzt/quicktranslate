#!/bin/bash
# 从 assets/logo-mark.svg 生成 AppIcon.icns，从 assets/menubar.svg 生成 menubar.png
# 优先用 rsvg-convert（透明背景、矢量逐尺寸渲染）；没有则回退 qlmanage
set -euo pipefail
ROOT="$HOME/quicktranslate"
SVG="$ROOT/assets/logo-mark.svg"
MBSVG="$ROOT/assets/menubar.svg"
WORK="$(mktemp -d)"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

HAS_RSVG=0; command -v rsvg-convert >/dev/null 2>&1 && HAS_RSVG=1

# 渲染 SVG 到指定边长的透明 PNG
render() { # <svg> <px> <out>
  if [ "$HAS_RSVG" = 1 ]; then
    rsvg-convert -w "$2" -h "$2" "$1" -o "$3"
  else
    qlmanage -t -s "$2" -o "$(dirname "$3")" "$1" >/dev/null 2>&1
    mv "$(dirname "$3")/$(basename "$1").png" "$3"
  fi
}

echo "==> 生成 app 图标各尺寸 (rsvg=$HAS_RSVG)"
for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
            "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" \
            "512 512x512" "1024 512x512@2x"; do
  set -- $spec
  render "$SVG" "$1" "$ICONSET/icon_$2.png"
done

echo "==> 合成 icns"
iconutil -c icns "$ICONSET" -o "$ROOT/assets/AppIcon.icns"

# 菜单栏单色模板
if [ -f "$MBSVG" ]; then
  echo "==> 生成菜单栏模板 menubar.png"
  if [ "$HAS_RSVG" = 1 ]; then
    rsvg-convert -w 144 -h 144 "$MBSVG" -o "$ROOT/assets/menubar.png"   # 黑形状 + 透明底, 直接可作模板
  else
    # 回退：qlmanage 出白底，按亮度反转成透明
    qlmanage -t -s 144 -o "$WORK" "$MBSVG" >/dev/null 2>&1
    cat > "$WORK/l.swift" <<'SW'
import AppKit
let a=CommandLine.arguments
let s=NSBitmapImageRep(data: NSImage(contentsOfFile:a[1])!.tiffRepresentation!)!
let w=s.pixelsWide,h=s.pixelsHigh
let o=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:w,pixelsHigh:h,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:w*4,bitsPerPixel:32)!
for y in 0..<h{for x in 0..<w{let c=s.colorAt(x:x,y:y)!;let l=c.redComponent*0.299+c.greenComponent*0.587+c.blueComponent*0.114;o.setColor(NSColor(deviceRed:0,green:0,blue:0,alpha:(1-l)*c.alphaComponent),atX:x,y:y)}}
try! o.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:a[2]))
SW
    xcrun -sdk macosx swiftc "$WORK/l.swift" -o "$WORK/l" 2>/dev/null \
      && "$WORK/l" "$WORK/$(basename "$MBSVG").png" "$ROOT/assets/menubar.png"
  fi
fi

rm -rf "$WORK"
echo "==> 完成: assets/AppIcon.icns + assets/menubar.png"
