#!/bin/sh
# POSIX shell, supports: curl | sh
set -eu

echo ">>> 开始卸载 claude-use ..."

INSTALL_ROOT="$HOME/.claude-tools"

# 0) 卸载前：若当前目录在 ~/.claude-tools 下，先切回家目录，避免删目录后 $PWD 失效
case "$PWD" in
  "$INSTALL_ROOT"|"$INSTALL_ROOT"/*)
    cd "$HOME"
    ;;
esac

# 1) 删除安装目录
if [ -d "$INSTALL_ROOT" ]; then
  rm -rf "$INSTALL_ROOT"
  echo "✓ 已删除目录 $INSTALL_ROOT"
else
  echo "ℹ 未发现 $INSTALL_ROOT"
fi

# 2) 清理 zshrc（考虑 ZDOTDIR）
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
if [ -f "$ZSHRC" ]; then
  TMP=$(mktemp)
  awk '
    /^# --- claude-tools BEGIN ---/ {flag=1; next}
    /^# --- claude-tools END ---/   {flag=0; next}
    flag==0 {print}
  ' "$ZSHRC" > "$TMP"
  mv "$TMP" "$ZSHRC"
  echo "✓ 已从 $ZSHRC 移除 claude-tools 配置块"
else
  echo "ℹ 未发现 $ZSHRC"
fi

echo
echo ">>> 卸载完成 🎉"
echo "提示：不会删除你的 API 配置文件（默认在 ~/.claude/envs）。如需彻底清理： rm -rf ~/.claude"