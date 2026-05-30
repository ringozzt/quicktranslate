#!/bin/bash
# 打包发布产物：dist/QuickTranslate-<ver>.zip 和 .dmg
set -euo pipefail
ROOT="$HOME/quicktranslate"
APP="$ROOT/build/QuickTranslate.app"
VER="${1:-1.0.0}"
DIST="$ROOT/dist"

# 1. 先构建最新 app
bash "$ROOT/build.sh"

rm -rf "$DIST"; mkdir -p "$DIST"

# 2. zip（保留签名与权限用 ditto）
echo "==> 打包 zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/QuickTranslate-$VER.zip"

# 3. dmg（拖拽到 Applications 安装）
echo "==> 打包 dmg"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "QuickTranslate" -srcfolder "$STAGE" \
  -ov -format UDZO "$DIST/QuickTranslate-$VER.dmg" >/dev/null
rm -rf "$STAGE"

echo "==> 产物："
ls -lh "$DIST"
shasum -a 256 "$DIST"/* | sed "s#$DIST/##"
