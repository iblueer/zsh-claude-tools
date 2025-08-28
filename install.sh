#!/bin/sh
# POSIX shell, supports: curl | sh
set -eu

echo ">>> 开始安装 claude-use ..."

# ================= 基本配置 =================
# 可选：通过环境变量切换 RAW 主机（网络不佳时有用）
# 例：export GITHUB_RAW_BASE=raw.fastgit.org
RAW_HOST="${GITHUB_RAW_BASE:-raw.githubusercontent.com}"
REPO_PATH="iblueer/zsh-claude-tools"
BRANCH="main"
BASE_URL="https://${RAW_HOST}/${REPO_PATH}/${BRANCH}"

INSTALL_ROOT="$HOME/.claude-tools"
BIN_DIR="$INSTALL_ROOT/bin"
COMP_DIR="$INSTALL_ROOT/completions"
mkdir -p "$BIN_DIR" "$COMP_DIR"

# ================= 下载函数（带重试与报错） =================
fetch() {
  url="$1"; dst="$2"
  echo "… 下载 $url"
  if ! curl -fL --retry 3 --retry-delay 1 -o "$dst" "$url"; then
    echo "✗ 下载失败：$url"
    echo "  提示：检查网络/代理，或设置 GITHUB_RAW_BASE 使用镜像后重试"
    exit 1
  fi
}

# 1) 下载核心脚本
fetch "$BASE_URL/bin/claude-use.zsh"      "$BIN_DIR/claude-use.zsh"
fetch "$BASE_URL/completions/_claude-use" "$COMP_DIR/_claude-use"

# 2) 创建默认环境目录与示例
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

# 3) 写入 ~/.zshrc（考虑 ZDOTDIR，安全追加，避免与上一行黏连）
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
BEGIN_MARK='# --- claude-tools BEGIN ---'
END_MARK='# --- claude-tools END ---'

ensure_newline() {
  file="$1"
  if [ -s "$file" ]; then
    # 若文件非空且末尾不是换行，补一个换行
    lastchar=$(LC_ALL=C tail -c 1 "$file" 2>/dev/null || true)
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

# 若用户尚未启用补全系统，则自动追加一次
if ! grep -Eqs '(^|[[:space:]])compinit([[:space:]]|$)' "$ZSHRC"; then
  ensure_newline "$ZSHRC"
  printf 'autoload -Uz compinit\ncompinit\n' >>"$ZSHRC"
fi

add_line_if_absent "$END_MARK" "$ZSHRC"

# 4) 结束提示（不自动 source，避免触发用户 zshrc 中的其他副作用）
echo
echo ">>> 安装完成 🎉"
echo "安装目录：$INSTALL_ROOT"
echo "环境目录：$ENV_DIR"
echo
echo "请执行： source ~/.zshrc"
echo "然后运行： claude-use list"