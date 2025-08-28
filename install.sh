#!/bin/sh
set -eu

echo ">>> 开始安装 claude-use ..."

INSTALL_ROOT="$HOME/.claude-tools"
BIN_DIR="$INSTALL_ROOT/bin"
COMP_DIR="$INSTALL_ROOT/completions"

mkdir -p "$BIN_DIR" "$COMP_DIR"

# GitHub Raw 基础路径（根据仓库地址修改）
BASE_URL="https://raw.githubusercontent.com/iblueer/zsh-claude-tools/main"

# 下载核心脚本
curl -fsSL "$BASE_URL/bin/claude-use.zsh" -o "$BIN_DIR/claude-use.zsh"
curl -fsSL "$BASE_URL/completions/_claude-use" -o "$COMP_DIR/_claude-use"

# 默认环境目录
: "${CLAUDE_CODE_HOME:="$HOME/.claude"}"
ENV_DIR="$CLAUDE_CODE_HOME/envs"
mkdir -p "$ENV_DIR"

DEFAULT_ENV="$ENV_DIR/default.env"
if [ ! -f "$DEFAULT_ENV" ]; then
  cat >"$DEFAULT_ENV" <<'E'
# 默认示例（请按需填写）
export ANTHROPIC_BASE_URL=""
export ANTHROPIC_AUTH_TOKEN=""
export ANTHROPIC_MODEL=""
export ANTHROPIC_SMALL_FAST_MODEL=""
E
  echo "✓ 已创建默认环境文件：$DEFAULT_ENV"
fi

# 修改 zshrc
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
BEGIN_MARK='# --- claude-tools BEGIN ---'
END_MARK='# --- claude-tools END ---'

ensure_newline() {
  file="$1"
  if [ -s "$file" ]; then
    lastchar=$(tail -c 1 "$file" || true)
    [ "$lastchar" != "" ] && printf '\n' >>"$file"
  fi
}

add_line_if_absent() {
  line="$1"; file="$2"
  if ! grep -Fqx "$line" "$file" 2>/dev/null; then
    ensure_newline "$file"
    printf '%s\n' "$line" >>"$file"
  fi
}

touch "$ZSHRC"
add_line_if_absent "$BEGIN_MARK" "$ZSHRC"
add_line_if_absent 'source "$HOME/.claude-tools/bin/claude-use.zsh"' "$ZSHRC"
add_line_if_absent 'fpath+=("$HOME/.claude-tools/completions")' "$ZSHRC"

if ! grep -Eqs '(^|[[:space:]])compinit([[:space:]]|$)' "$ZSHRC"; then
  ensure_newline "$ZSHRC"
  printf 'autoload -Uz compinit\ncompinit\n' >>"$ZSHRC"
fi

add_line_if_absent "$END_MARK" "$ZSHRC"

echo
echo ">>> 安装完成 🎉"
echo "安装目录：$INSTALL_ROOT"
echo "环境目录：$ENV_DIR"
echo
echo "请执行： source ~/.zshrc"
echo "然后运行： claude-use list"