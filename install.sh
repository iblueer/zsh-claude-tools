#!/bin/sh
# POSIX; supports: curl | sh
# Debug trace: CLAUDE_TOOLS_DEBUG=1 curl .../install.sh | sh
set -eu
[ "${CLAUDE_TOOLS_DEBUG:-0}" = "1" ] && set -x

# ----- error trap -----
on_err() {
  code=$?
  echo "✗ 安装失败 (exit=$code)。可能是网络/权限/文件系统问题。" >&2
  echo "提示：若启用了代理可尝试关闭；或设置镜像：export GITHUB_RAW_BASE=raw.fastgit.org 后重试。" >&2
  exit "$code"
}
trap 'on_err' ERR

echo ">>> 开始安装 claude-use ..."

# ===== Step 0. 基础配置与目录 =====
RAW_HOST="${GITHUB_RAW_BASE:-raw.githubusercontent.com}"
REPO_PATH="iblueer/zsh-claude-tools"
BRANCH="main"
BASE_URL="https://${RAW_HOST}/${REPO_PATH}/${BRANCH}"

INSTALL_ROOT="$HOME/.claude-tools"
BIN_DIR="$INSTALL_ROOT/bin"
COMP_DIR="$INSTALL_ROOT/completions"
SHELL_NAME="$(basename "${CLAUDE_TOOLS_SHELL:-${SHELL:-}}")"
case "$SHELL_NAME" in
  bash) INIT_FILE="$INSTALL_ROOT/init.bash" ;;
  *) SHELL_NAME=zsh; INIT_FILE="$INSTALL_ROOT/init.zsh" ;;
esac

# 项目标记（可通过 CLAUDE_PROJECT_ID 覆盖）
PROJECT_ID="${CLAUDE_PROJECT_ID:-iblueer/zsh-claude-tools}"
BEGIN_MARK="# >>> ${PROJECT_ID} BEGIN (managed) >>>"
END_MARK="# <<< ${PROJECT_ID} END   <<<"

echo "[Step 0] 初始化目录：$INSTALL_ROOT"
mkdir -p "$BIN_DIR" "$COMP_DIR"

# ===== Step 1. 下载核心文件（带重试） =====
fetch() {
  url="$1"; dst="$2"
  echo "[Step 1] 下载 $url -> $dst"
  curl -fL --retry 3 --retry-delay 1 -o "$dst" "$url"
}
fetch "$BASE_URL/bin/claude-use.zsh"      "$BIN_DIR/claude-use.zsh"
fetch "$BASE_URL/bin/claude-use.bash"     "$BIN_DIR/claude-use.bash"
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

# ===== Step 3. 生成 init 脚本 =====
if [ "$SHELL_NAME" = "bash" ]; then
  echo "[Step 3] 生成 init：$INIT_FILE"
  cat >"$INIT_FILE" <<'EINIT'
# zsh-claude-tools init for bash (auto-generated)
: ${CLAUDE_CODE_HOME:="$HOME/.claude"}
if [ -f "$HOME/.claude-tools/bin/claude-use.bash" ]; then
  . "$HOME/.claude-tools/bin/claude-use.bash"
fi
EINIT
else
  echo "[Step 3] 生成 init：$INIT_FILE"
  cat >"$INIT_FILE" <<'EINIT'
# zsh-claude-tools init (auto-generated)
# 幂等：尽量避免重复影响用户环境

# 环境目录（若用户未设置）
: ${CLAUDE_CODE_HOME:="$HOME/.claude"}

# 补全目录（若未包含则追加）
case ":$fpath:" in
  *":$HOME/.claude-tools/completions:"*) ;;
  *) fpath+=("$HOME/.claude-tools/completions");;
esac

# 加载函数本体（仅交互式 zsh）
case "$-" in
  *i*)
    if [ -f "$HOME/.claude-tools/bin/claude-use.zsh" ]; then
      . "$HOME/.claude-tools/bin/claude-use.zsh"
    fi
    ;;
esac

# 补全未初始化则初始化一次
if ! typeset -f _main_complete >/dev/null 2>&1; then
  autoload -Uz compinit
  compinit
fi
EINIT
fi

# ===== Step 4. 幂等修改 rc 文件：唯一标记 + 原子替换 =====
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

# 确保 rc 存在
[ -f "$RC" ] || : > "$RC"

# 先移除旧块（仅匹配整行唯一标记），再在尾部追加新块；用 mktemp 原子替换
TMP_RC="$(mktemp)"
awk -v begin="$BEGIN_MARK" -v end="$END_MARK" '
  BEGIN { skip=0 }
  $0 == begin { skip=1; next }
  $0 == end   { skip=0; next }
  skip==0 { print }
' "$RC" > "$TMP_RC"

{
  printf "%s\n" "$BEGIN_MARK"
  if [ "$SHELL_NAME" = "bash" ]; then
    printf '%s\n' 'source "$HOME/.claude-tools/init.bash"'
  else
    printf '%s\n' 'source "$HOME/.claude-tools/init.zsh"'
  fi
  printf "%s\n" "$END_MARK"
} >> "$TMP_RC"

# 末尾确保换行
LC_ALL=C tail -c 1 "$TMP_RC" >/dev/null 2>&1 || printf '\n' >>"$TMP_RC"

# 原子替换
mv "$TMP_RC" "$RC"

# ===== Step 5. 完成提示 =====
echo
echo ">>> 安装完成 🎉"
echo "安装目录：$INSTALL_ROOT"
echo "环境目录：$ENV_DIR"
echo
echo "请执行： source \"$RC\""
echo "然后运行： claude-use list"

