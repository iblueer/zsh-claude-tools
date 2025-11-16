#!/usr/bin/env bash
# 本地离线安装脚本 - 用于无法访问GitHub的服务器
# 使用方式：
#   1. 将整个项目目录打包上传到服务器
#   2. 解压后进入项目目录
#   3. 执行: ./install_locally.sh
#
# Debug trace: CLAUDE_TOOLS_DEBUG=1 ./install_locally.sh
set -eu
[ "${CLAUDE_TOOLS_DEBUG:-0}" = "1" ] && set -x

on_err() {
  code=$?
  echo "✗ 安装失败 (exit=$code)。可能是权限/文件系统问题。" >&2
  exit "$code"
}
trap 'on_err' ERR

echo ">>> 开始本地安装 claude-switch ..."

# 获取脚本所在目录(即项目源码目录)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "[Info] 项目源码目录: $SCRIPT_DIR"

# 检查必要文件是否存在
if [ ! -f "$SCRIPT_DIR/bin/claude-switch.zsh" ] || \
   [ ! -f "$SCRIPT_DIR/bin/claude-switch.bash" ] || \
   [ ! -f "$SCRIPT_DIR/completions/_claude-switch" ]; then
  echo "✗ 错误: 项目源码不完整,请确认以下文件存在:" >&2
  echo "  - bin/claude-switch.zsh" >&2
  echo "  - bin/claude-switch.bash" >&2
  echo "  - completions/_claude-switch" >&2
  exit 1
fi

INSTALL_ROOT="$HOME/.claude-tools"
BIN_DIR="$INSTALL_ROOT/bin"
COMP_DIR="$INSTALL_ROOT/completions"
SHELL_NAME="$(basename "${CLAUDE_TOOLS_SHELL:-${SHELL:-}}")"
case "$SHELL_NAME" in
  bash) INIT_FILE="$INSTALL_ROOT/init.bash" ;;
  *) SHELL_NAME=zsh; INIT_FILE="$INSTALL_ROOT/init.zsh" ;;
esac

PROJECT_ID="${CLAUDE_PROJECT_ID:-iblueer/zsh-claude-tools}"
BEGIN_MARK="# >>> ${PROJECT_ID} BEGIN (managed) >>>"
END_MARK="# <<< ${PROJECT_ID} END   <<<"

echo "[Step 0] 初始化目录：$INSTALL_ROOT"
mkdir -p "$BIN_DIR" "$COMP_DIR"

# 从本地复制文件而非下载
echo "[Step 1] 复制脚本文件到 $BIN_DIR"
cp -f "$SCRIPT_DIR/bin/claude-switch.zsh" "$BIN_DIR/claude-switch.zsh"
cp -f "$SCRIPT_DIR/bin/claude-switch.bash" "$BIN_DIR/claude-switch.bash"
cp -f "$SCRIPT_DIR/bin/claude-use.zsh" "$BIN_DIR/claude-use.zsh"
cp -f "$SCRIPT_DIR/bin/claude-use.bash" "$BIN_DIR/claude-use.bash"
echo "[Step 1] 复制补全文件到 $COMP_DIR"
cp -f "$SCRIPT_DIR/completions/_claude-switch" "$COMP_DIR/_claude-switch"
cp -f "$SCRIPT_DIR/completions/_claude-use" "$COMP_DIR/_claude-use"

: "${CLAUDE_HOME:="$HOME/.claude"}"
ENV_DIR="$CLAUDE_HOME/envs"

echo "[Step 2] 准备环境目录：$ENV_DIR"
mkdir -p "$ENV_DIR"

DEFAULT_ENV="$ENV_DIR/default.env"
if [ ! -f "$DEFAULT_ENV" ]; then
  echo "[Step 2] 写入默认环境文件：$DEFAULT_ENV"
  cat >"$DEFAULT_ENV" <<'E'
# Claude Code API 环境模板：请按需修改
export ANTHROPIC_BASE_URL="https://anyrouter.top"
export ANTHROPIC_AUTH_TOKEN=""
export ANTHROPIC_MODEL="claude-3-7-sonnet"
export ANTHROPIC_SMALL_FAST_MODEL="claude-3-haiku"
E
  chmod 600 "$DEFAULT_ENV" 2>/dev/null || true
fi

if [ "$SHELL_NAME" = "bash" ]; then
  echo "[Step 3] 生成 init：$INIT_FILE"
  cat >"$INIT_FILE" <<'EINIT'
# zsh-claude-tools init for bash (auto-generated)
: ${CLAUDE_HOME:="$HOME/.claude"}
if [ -f "$HOME/.claude-tools/bin/claude-switch.bash" ]; then
  . "$HOME/.claude-tools/bin/claude-switch.bash"
fi
EINIT
else
  echo "[Step 3] 生成 init：$INIT_FILE"
  cat >"$INIT_FILE" <<'EINIT'
# zsh-claude-tools init (auto-generated)
# 幂等：尽量避免重复影响用户环境

: ${CLAUDE_HOME:="$HOME/.claude"}

case ":$fpath:" in
  *":$HOME/.claude-tools/completions:"*) ;;
  *) fpath+=("$HOME/.claude-tools/completions");;
esac

case "$-" in
  *i*)
    if [ -f "$HOME/.claude-tools/bin/claude-switch.zsh" ]; then
      . "$HOME/.claude-tools/bin/claude-switch.zsh"
    fi
    ;;
esac

if ! typeset -f _main_complete >/dev/null 2>&1; then
  autoload -Uz compinit
  compinit
fi
EINIT
fi

if [ "$SHELL_NAME" = "bash" ]; then
  RC="$HOME/.bashrc"
  echo "[Step 4] 更新 Bash 配置：$RC （标记：$PROJECT_ID ）"
else
  if [ -n "${ZDOTDIR:-}" ]; then
    RC="$ZDOTDIR/.zshrc"
  else
    RC="$HOME/.zshrc"
  fi
  echo "[Step 4] 更新 Zsh 配置：$RC （标记：$PROJECT_ID ）"
fi

[ -f "$RC" ] || : >"$RC"

TMP_RC="$(mktemp)"
awk -v begin="$BEGIN_MARK" -v end="$END_MARK" '
  BEGIN { skip=0 }
  $0 == begin { skip=1; next }
  $0 == end   { skip=0; next }
  skip==0 { print }
' "$RC" >"$TMP_RC"

{
  printf "%s\n" "$BEGIN_MARK"
  if [ "$SHELL_NAME" = "bash" ]; then
    printf '%s\n' 'source "$HOME/.claude-tools/init.bash"'
  else
    printf '%s\n' 'source "$HOME/.claude-tools/init.zsh"'
  fi
  printf "%s\n" "$END_MARK"
} >>"$TMP_RC"

LC_ALL=C tail -c 1 "$TMP_RC" >/dev/null 2>&1 || printf '\n' >>"$TMP_RC"

mv "$TMP_RC" "$RC"

echo
echo ">>> 本地安装完成 🎉"
echo "安装目录：$INSTALL_ROOT"
echo "环境目录：$ENV_DIR"
echo
echo "请执行： source \"$RC\""
echo "然后运行： claude-switch list"
