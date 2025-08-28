#!/bin/sh
# POSIX; supports: curl | sh
# Debug: CLAUDE_TOOLS_DEBUG=1 curl .../install.sh | sh
set -eu

[ "${CLAUDE_TOOLS_DEBUG:-0}" = "1" ] && set -x

# ----- error trap -----
on_err() {
  code=$?
  echo "✗ 安装失败 (exit=$code)。出错位置：行 $1，命令：$2" >&2
  echo "提示：可以设置镜像：export GITHUB_RAW_BASE=raw.fastgit.org 后重试" >&2
  exit $code
}
# $LINENO 在 /bin/sh 不总是可用，但大多数系统可用；command expansion 则通过 $BASH_COMMAND 不可用，所以传入 $0
trap 'on_err "$LINENO" "$0"' ERR

echo ">>> 开始安装 claude-use ..."

# ===== Step 0. 基础配置 =====
RAW_HOST="${GITHUB_RAW_BASE:-raw.githubusercontent.com}"
REPO_PATH="iblueer/zsh-claude-tools"
BRANCH="main"
BASE_URL="https://${RAW_HOST}/${REPO_PATH}/${BRANCH}"

INSTALL_ROOT="$HOME/.claude-tools"
BIN_DIR="$INSTALL_ROOT/bin"
COMP_DIR="$INSTALL_ROOT/completions"
echo "[Step 0] 初始化目录：$INSTALL_ROOT"
mkdir -p "$BIN_DIR" "$COMP_DIR"

# 带重试的下载
fetch() {
  url="$1"; dst="$2"
  echo "[Step 1] 下载 $url -> $dst"
  curl -fL --retry 3 --retry-delay 1 -o "$dst" "$url"
}

# ===== Step 1. 下载核心文件 =====
fetch "$BASE_URL/bin/claude-use.zsh"      "$BIN_DIR/claude-use.zsh"
fetch "$BASE_URL/completions/_claude-use" "$COMP_DIR/_claude-use"

# ===== Step 2. 环境目录与默认示例 =====
: "${CLAUDE_CODE_HOME:="$HOME/.claude"}"
ENV_DIR="$CLAUDE_CODE_HOME/envs"
echo "[Step 2] 准备环境目录：$ENV_DIR"
mkdir -p "$ENV_DIR"

DEFAULT_ENV="$ENV_DIR/default.env"
if [ ! -f "$DEFAULT_ENV" ]; then
  echo "[Step 2] 写入默认环境文件：$DEFAULT_ENV"
  cat >"$DEFAULT_ENV" <<'E'
# 默认示例（请按需填写）
export ANTHROPIC_BASE_URL=""
export ANTHROPIC_AUTH_TOKEN=""
export ANTHROPIC_MODEL=""
export ANTHROPIC_SMALL_FAST_MODEL=""
E
fi

# ===== Step 3. 写入 ~/.zshrc =====
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
BEGIN_MARK='# --- claude-tools BEGIN ---'
END_MARK='# --- claude-tools END ---'

ensure_newline() {
  file="$1"
  if [ -s "$file" ]; then
    # 若最后一字节不是换行，则补一行（BSD/GNU 通用）
    lastchar=$(LC_ALL=C tail -c 1 "$file" 2>/dev/null || true)
    [ "$lastchar" != "" ] && printf '\n' >>"$file"
  fi
}
add_line_if_absent() {
  line="$1"; file="$2"
  # 整行匹配；文件不存在时 grep 返回 2，这里先 touch 避免
  touch "$file"
  if ! grep -Fqx "$line" "$file" 2>/dev/null; then
    ensure_newline "$file"
    printf '%s\n' "$line" >>"$file"
  fi
}

echo "[Step 3] 更新 Zsh 配置：$ZSHRC"
add_line_if_absent "$BEGIN_MARK" "$ZSHRC"
add_line_if_absent 'source "$HOME/.claude-tools/bin/claude-use.zsh"' "$ZSHRC"
add_line_if_absent 'fpath+=("$HOME/.claude-tools/completions")' "$ZSHRC"

# 若用户还未启用补全系统，则自动追加一次
if ! grep -Eqs '(^|[[:space:]])compinit([[:space:]]|$)' "$ZSHRC"; then
  echo "[Step 3] 启用 zsh 补全（compinit）"
  ensure_newline "$ZSHRC"
  printf 'autoload -Uz compinit\ncompinit\n' >>"$ZSHRC"
fi
add_line_if_absent "$END_MARK" "$ZSHRC"

# ===== Step 4. 完成提示 =====
echo
echo ">>> 安装完成 🎉"
echo "安装目录：$INSTALL_ROOT"
echo "环境目录：$ENV_DIR"
echo
echo "请执行： source ~/.zshrc"
echo "然后运行： claude-use list"