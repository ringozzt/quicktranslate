#!/bin/bash
# QuickTranslate 一键安装 / One-line installer
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ringozzt/quicktranslate/main/install.sh)"
set -euo pipefail

REPO="https://github.com/ringozzt/quicktranslate.git"
DIR="${QT_DIR:-$HOME/quicktranslate}"
SHORTCUT="Bob.Translate.v2"

bold() { printf "\033[1m%s\033[0m\n" "$1"; }
ok()   { printf "\033[32m✓\033[0m %s\n" "$1"; }
warn() { printf "\033[33m!\033[0m %s\n" "$1"; }
die()  { printf "\033[31m✗ %s\033[0m\n" "$1"; exit 1; }

bold "==> QuickTranslate 一键安装"

# 1. 环境检查
[[ "$(uname)" == "Darwin" ]] || die "本工具仅支持 macOS"
command -v git >/dev/null 2>&1 || die "缺少 git"
xcrun -sdk macosx --find swiftc >/dev/null 2>&1 \
  || die "缺少 Xcode 命令行工具，请先运行: xcode-select --install"
ok "macOS / git / swiftc 就绪"

# 2. 获取代码
if [[ -d "$DIR/.git" ]]; then
  bold "==> 更新已有仓库 $DIR"
  git -C "$DIR" pull --ff-only
else
  bold "==> 克隆到 $DIR"
  git clone --depth 1 "$REPO" "$DIR"
fi

# 3. 构建
bold "==> 编译"
bash "$DIR/build.sh"

# 4. 检查翻译快捷指令
if shortcuts list 2>/dev/null | grep -qx "$SHORTCUT"; then
  ok "已检测到快捷指令「$SHORTCUT」"
else
  warn "未检测到快捷指令「$SHORTCUT」——翻译会无法工作。"
  warn "解决：安装 Bob 并开启一次系统翻译，或按 README「准备快捷指令」自建同名快捷指令。"
fi

# 5. 启动
bold "==> 启动 QuickTranslate"
open "$DIR/build/QuickTranslate.app"

cat <<'EOF'

────────────────────────────────────────────
✅ 安装完成！菜单栏右上角会出现「译」图标。

还差最后一步（一次性授权）：
  系统设置 › 隐私与安全性 › 辅助功能 → 打开 QuickTranslate
  然后点菜单栏「译 → 退出」再重新打开 app。

用法：任意 App 选中文字 → 按 ⌥D → 光标旁弹出译文。
────────────────────────────────────────────
EOF
