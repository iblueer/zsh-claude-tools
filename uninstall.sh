#!/usr/bin/env bash
set -euo pipefail

echo ">>> 开始卸载 claude-use ..."

# 1. 删除安装目录
INSTALL_ROOT="$HOME/.claude-tools"
if [[ -d "$INSTALL_ROOT" ]]; then
  rm -rf "$INSTALL_ROOT"
  echo "✓ 删除目录 $INSTALL_ROOT"
else
  echo "ℹ 未发现 $INSTALL_ROOT"
fi

# 2. 清理 ~/.zshrc
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
if [[ -f "$ZSHRC" ]]; then
  TMP="$(mktemp)"
  awk '
    /^# --- claude-tools BEGIN ---/ {flag=1; next}
    /^# --- claude-tools END ---/   {flag=0; next}
    flag==0 {print}
  ' "$ZSHRC" > "$TMP"
  mv "$TMP" "$ZSHRC"
  echo "✓ 已从 $ZSHRC 移除 claude-tools 配置"
else
  echo "ℹ 未发现 $ZSHRC"
fi

echo ">>> 卸载完成。"
echo "提示：如果你也要删除保存的 API 配置，可执行： rm -rf ~/.claude"