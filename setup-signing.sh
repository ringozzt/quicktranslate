#!/bin/bash
# 一次性创建本地自签名代码签名证书，导入登录钥匙串。
# 作用：用固定证书签名后，macOS 的辅助功能/屏幕录制授权依据是「证书」而非每次都变的 cdhash，
#      因此重新编译、更新、重装后授权都不会失效（不用反复去系统设置里重新勾选）。
set -euo pipefail
CN="QuickTranslate Local Signing"

if security find-identity -p codesigning 2>/dev/null | grep -q "$CN"; then
  echo "✓ 签名身份已存在：$CN"
  exit 0
fi

echo "==> 生成自签名证书 ($CN)"
TMP="$(mktemp -d)"; cd "$TMP"
openssl req -x509 -newkey rsa:2048 -keyout k.pem -out c.pem -days 3650 -nodes \
  -subj "/CN=$CN" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature" >/dev/null 2>&1

# -legacy: macOS security 才能读取 OpenSSL 3 生成的 p12
openssl pkcs12 -export -legacy -inkey k.pem -in c.pem -out id.p12 -passout pass:qt -name "$CN" >/dev/null 2>&1

echo "==> 导入登录钥匙串"
security import id.p12 -k "$HOME/Library/Keychains/login.keychain-db" -P qt -T /usr/bin/codesign -A
cd - >/dev/null; rm -rf "$TMP"

echo "✓ 完成。现在 ./build.sh 会自动用该证书签名。"
echo "  首次签名若弹钥匙串授权框，点「始终允许」。"
