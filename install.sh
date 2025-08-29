#!/bin/sh
# POSIX; supports: curl | sh
# Debug trace: CLAUDE_TOOLS_DEBUG=1 curl .../install.sh | sh
set -eu
[ "${CLAUDE_TOOLS_DEBUG:-0}" = "1" ] && set -x

# ----- error trap -----
on_err() {
  code=$?
  echo "✗ 安装失败 (exit=$code)。可能是网络/权限/文件系统问题。" >&2
  echo "提示1：若启用了代理，尝试关闭或用直连再试。" >&2
  echo "提示2：可设置镜像：export GITHUB_RAW_BASE=raw.fastgit.org  然后再运行安装命令。" >&2
  exit $code
}
trap 'on_err' ERR

echo ">>> 开始安装 claude-use ..."

# ===== Step 0. 配置与目录 =====
RAW_HOST="${GITHUB_RAW_BASE:-raw.githubusercontent.com}"
REPO_PATH="iblueer/zsh-claude-tools"
BRANCH="main"
BASE_URL="https://${RAW_HOST}/${REPO_PATH}/${BRANCH}"

INSTALL_ROOT="$HOME/.claude-tools"
BIN_DIR="$INSTALL_ROOT/bin"
COMP_DIR="$INSTALL_ROOT/completions"
echo "[Step 0] 初始化目录：$INSTALL_ROOT"
mkdir -p "$BIN_DIR" "$COMP_DIR"

# ===== Step 1. 下载核心文件 =====
fetch() {
  url="$1"; dst="$2"
  echo "[Step 1] 下载 $url -> $dst"
  curl -fL --retry 3 --retry-delay 1 -o "$dst" "$url"
}
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

# ===== Step 3. 幂等写入 ~/.zshrc =====
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
BEGIN_MARK='# --- claude-tools BEGIN ---'
END_MARK='# --- claude-tools END ---'
echo "[Step 3] 更新 Zsh 配置：$ZSHRC"

# 确保 rc 文件存在
[ -f "$ZSHRC" ] || : > "$ZSHRC"

# 先去掉旧块，再在尾部追加新块（原子写）
TMP_RC="$(mktemp)"
awk -v begin="$BEGIN_MARK" -v end="$END_MARK" '
  BEGIN { skip=0 }
  $0 ~ begin { skip=1; next }
  $0 ~ end   { skip=0; next }
  skip==0 { print }
' "$ZSHRC" > "$TMP_RC"

{
  printf "%s\n" "$BEGIN_MARK"
  printf '%s\n' 'source "$HOME/.claude-tools/bin/claude-use.zsh"'
  printf '%s\n' 'fpath+=("$HOME/.claude-tools/completions")'
  # 若已存在 compinit 用户仍可保留，但这里追加一份保证可用
  printf '%s\n' 'autoload -Uz compinit'
  printf '%s\n' 'compinit'
  printf "%s\n" "$END_MARK"
} >> "$TMP_RC"

# 确保以换行结尾（美观且安全）
# shellcheck disable=SC2016
tail -c 1 "$TMP_RC" >/dev/null 2>&1 || printf '\n' >>"$TMP_RC"

mv "$TMP_RC" "$ZSHRC"

# ===== Step 4. 完成提示 =====
echo
echo ">>> 安装完成 🎉"
echo "安装目录：$INSTALL_ROOT"
echo "环境目录：$ENV_DIR"
echo
echo "请执行： source ~/.zshrc"
echo "然后运行： claude-use list"