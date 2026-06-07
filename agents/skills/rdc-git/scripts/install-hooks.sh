#!/bin/sh
#
# install-hooks.sh
# 一键安装 Git hooks 到当前仓库
#
# 用法:
#   ./install-hooks.sh
#   或在项目根目录执行: sh path/to/install-hooks.sh
#

set -e

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 检查是否在 Git 仓库中
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Error: 当前目录不是 Git 仓库"
    echo "请在 Git 仓库根目录执行此脚本"
    exit 1
fi

# 获取 .git/hooks 目录
GIT_DIR=$(git rev-parse --git-dir)
HOOKS_DIR="$GIT_DIR/hooks"

echo "Installing Git hooks..."
echo ""

# 创建 hooks 目录 (如果不存在)
mkdir -p "$HOOKS_DIR"

# 安装 commit-msg hook
if [ -f "$SCRIPT_DIR/commit-msg" ]; then
    cp "$SCRIPT_DIR/commit-msg" "$HOOKS_DIR/commit-msg"
    chmod +x "$HOOKS_DIR/commit-msg"
    echo "[OK] commit-msg hook installed"
else
    echo "[SKIP] commit-msg not found"
fi

# 安装 pre-commit hook
if [ -f "$SCRIPT_DIR/pre-commit" ]; then
    cp "$SCRIPT_DIR/pre-commit" "$HOOKS_DIR/pre-commit"
    chmod +x "$HOOKS_DIR/pre-commit"
    echo "[OK] pre-commit hook installed"
else
    echo "[SKIP] pre-commit not found"
fi

echo ""
echo "=================================================="
echo "  Git hooks 安装完成!"
echo "=================================================="
echo ""
echo "已安装的 hooks:"
echo "  - commit-msg: 验证 commit message 格式"
echo "  - pre-commit: 检查敏感文件和大文件"
echo ""
echo "hooks 位置: $HOOKS_DIR"
echo ""
