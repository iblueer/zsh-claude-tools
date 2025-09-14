#!/bin/sh
# POSIX shell, supports: curl | sh
set -eu

echo ">>> 开始卸载 claude-use ..."

INSTALL_ROOT="$HOME/.claude-tools"
PROJECT_ID="${CLAUDE_PROJECT_ID:-iblueer/zsh-claude-tools}"
BEGIN_MARK="# >>> ${PROJECT_ID} BEGIN (managed) >>>"
END_MARK="# <<< ${PROJECT_ID} END   <<<"

# 0) 若当前目录在安装目录下，先切回家目录
case "$PWD" in
  "$INSTALL_ROOT"|"$INSTALL_ROOT"/*) cd "$HOME" ;;
esac

# 1) 删除安装目录
if [ -d "$INSTALL_ROOT" ]; then
  rm -rf "$INSTALL_ROOT"
  echo "✓ 已删除目录 $INSTALL_ROOT"
else
  echo "ℹ 未发现 $INSTALL_ROOT"
fi

remove_block() {
  file="$1"
  if [ -f "$file" ]; then
    tmp=$(mktemp)
    awk -v begin="$BEGIN_MARK" -v end="$END_MARK" '
      $0 == begin {skip=1; next}
      $0 == end {skip=0; next}
      skip==0 {print}
    ' "$file" >"$tmp"
    mv "$tmp" "$file"
    echo "✓ 已从 $file 移除 claude-tools 配置块"
  else
    echo "ℹ 未发现 $file"
  fi
}

remove_block "${ZDOTDIR:-$HOME}/.zshrc"
remove_block "$HOME/.bashrc"

echo
echo ">>> 卸载完成 🎉"
echo "提示：不会删除你的 API 配置文件（默认在 ~/.claude/envs）。如需彻底清理： rm -rf ~/.claude"
