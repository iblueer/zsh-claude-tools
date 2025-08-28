#!/bin/sh
set -eu

echo ">>> 开始卸载 claude-use ..."

# 删除安装目录
INSTALL_ROOT="$HOME/.claude-tools"
if [ -d "$INSTALL_ROOT" ]; then
  rm -rf "$INSTALL_ROOT"
  echo "✓ 已删除目录 $INSTALL_ROOT"
else
  echo "ℹ 未发现 $INSTALL_ROOT"
fi

# 清理 zshrc 配置块
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
echo "提示：如果你也想删除 API 配置文件，可执行： rm -rf ~/.claude"