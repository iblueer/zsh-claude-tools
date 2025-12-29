#!/usr/bin/env bash
# Claude Code API 环境管理工具（Bash/Git Bash）
# 配置项：
#   CLAUDE_CODE_HOME        默认 $HOME/.claude   => 环境目录位于 $CLAUDE_CODE_HOME/envs
#   CLAUDE_USE_EDITOR_CMD   覆盖编辑器命令，例如：export CLAUDE_USE_EDITOR_CMD="code -w"

: "${CLAUDE_CODE_HOME:="$HOME/.claude"}"
CLAUDE_USE_ENV_DIR="$CLAUDE_CODE_HOME/envs"
CLAUDE_USE_LAST="$CLAUDE_USE_ENV_DIR/last_choice"

_cu_info() { printf '▸ %s\n' "$*"; }
_cu_warn() { printf '⚠ %s\n' "$*"; }
_cu_err()  { printf '✗ %s\n' "$*"; }
_cu_ok()   { printf '✓ %s\n' "$*"; }

# Claude settings sync (~/.claude/settings.json)
_cu_claude_settings_path() {
  printf '%s\n' "$CLAUDE_CODE_HOME/settings.json"
}

_cu_sync_claude_settings() {
  command -v python3 >/dev/null 2>&1 || return 0
  [ -d "$CLAUDE_CODE_HOME" ] || mkdir -p "$CLAUDE_CODE_HOME" >/dev/null 2>&1 || true

  local settings_path
  settings_path="$(_cu_claude_settings_path)" || return 0

  python3 - "$settings_path" <<'PY' >/dev/null 2>&1 || true
import json
import os
import sys
import tempfile

settings_path = sys.argv[1]
prefix = "ANTHROPIC_"

try:
    with open(settings_path, "r", encoding="utf-8") as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}
except Exception:
    sys.exit(0)

if not isinstance(data, dict):
    data = {}

env_obj = data.get("env")
if not isinstance(env_obj, dict):
    env_obj = {}

desired = {k: v for k, v in os.environ.items() if k.startswith(prefix)}

model = desired.get("ANTHROPIC_MODEL")
small_fast = desired.get("ANTHROPIC_SMALL_FAST_MODEL")

if model is not None and model != "":
    desired["ANTHROPIC_DEFAULT_SONNET_MODEL"] = model
else:
    desired.pop("ANTHROPIC_DEFAULT_SONNET_MODEL", None)

if small_fast is not None and small_fast != "":
    desired["ANTHROPIC_DEFAULT_HAIKU_MODEL"] = small_fast
else:
    desired.pop("ANTHROPIC_DEFAULT_HAIKU_MODEL", None)

for k in list(env_obj.keys()):
    if isinstance(k, str) and k.startswith(prefix) and k not in desired:
        env_obj.pop(k, None)

for k, v in desired.items():
    env_obj[k] = v

data["env"] = env_obj

if model is not None and model != "":
    data["model"] = model

tmp_dir = os.path.dirname(settings_path) or "."
with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False, dir=tmp_dir) as tf:
    json.dump(data, tf, ensure_ascii=False, indent=2)
    tf.write("\\n")
    tmp_name = tf.name

os.replace(tmp_name, settings_path)
PY
}

# Detect whether running on Windows (Git Bash / MSYS2 / Cygwin)
_cu_is_windows() {
  case "$OSTYPE" in
    cygwin*|msys*|win32*|mingw*) return 0 ;;
    *) return 1 ;;
  esac
}

# Simple spinner for long-running operations
_cu_with_spinner() {
  local msg="$1"; shift
  printf "%s " "$msg"
  {
    local frames=('|' '/' '-' '\\')
    local i=0
    while :; do
      printf "\r%s %s" "$msg" "${frames[i]}"
      i=$(( (i + 1) % 4 ))
      sleep 0.1
    done
  } &
  local spid=$!
  disown "$spid" 2>/dev/null || true
  "$@"
  local ret=$?
  kill "$spid" 2>/dev/null
  wait "$spid" 2>/dev/null || true
  printf "\r%s\n" "$msg"
  return $ret
}

_cu_ensure_envdir() { [ -d "$CLAUDE_USE_ENV_DIR" ] || mkdir -p "$CLAUDE_USE_ENV_DIR"; }

_cu_list_names() {
  _cu_ensure_envdir
  local f rel
  # 使用 find 递归查找所有 .env 文件
  if command -v find >/dev/null 2>&1; then
    while IFS= read -r f; do
      # 计算相对路径并移除 .env 后缀
      rel="${f#$CLAUDE_USE_ENV_DIR/}"
      printf '%s\n' "${rel%.env}"
    done < <(command find "$CLAUDE_USE_ENV_DIR" -type f -name '*.env' 2>/dev/null | LC_ALL=C sort)
  else
    # 降级：只显示第一层（兼容没有 find 的系统）
    for f in "$CLAUDE_USE_ENV_DIR"/*.env; do
      [ -e "$f" ] || continue
      f="$(basename "${f%.env}")"
      printf '%s\n' "$f"
    done
  fi
}

_cu_open_path() {
  local path="$1"
  if _cu_is_windows; then
    local winpath="$path"
    if command -v cygpath >/dev/null 2>&1; then
      winpath="$(cygpath -w "$path")"
    fi
    if [ -d "$path" ]; then
      if command -v code >/dev/null 2>&1; then code -w "$winpath" && return 0; fi
      if command -v explorer.exe >/dev/null 2>&1; then explorer.exe "$winpath" && return 0; fi
    else
      if command -v code >/dev/null 2>&1; then code -w "$winpath" && return 0; fi
      if command -v notepad.exe >/dev/null 2>&1; then notepad.exe "$winpath" && return 0; fi
    fi
    if command -v cmd.exe >/dev/null 2>&1; then
      cmd.exe /c start "" "$winpath" >/dev/null 2>&1 && return 0
    fi
    _cu_warn "请手动打开：$path"
    return 0
  fi
  if [ -n "${CLAUDE_USE_EDITOR_CMD:-}" ]; then
    if eval "$CLAUDE_USE_EDITOR_CMD \"$path\""; then
      return 0
    else
      _cu_warn "自定义编辑器命令失败：$CLAUDE_USE_EDITOR_CMD"
    fi
  fi
  if [ -d "$path" ]; then
    if command -v code >/dev/null 2>&1; then code -w "$path" && return 0; fi
    if command -v code-insiders >/dev/null 2>&1; then code-insiders -w "$path" && return 0; fi
    if command -v subl >/dev/null 2>&1; then subl -w "$path" && return 0; fi
    if command -v xdg-open >/dev/null 2>&1; then xdg-open "$path" && return 0; fi
    if [ -n "${VISUAL:-}" ]; then "$VISUAL" "$path" && return 0; fi
    if [ -n "${EDITOR:-}" ]; then "$EDITOR" "$path" && return 0; fi
    if command -v vim >/dev/null 2>&1; then vim "$path" && return 0; fi
    if command -v nvim >/dev/null 2>&1; then nvim "$path" && return 0; fi
    _cu_warn "请手动打开：$path"
    return 0
  fi
  if [ -n "${VISUAL:-}" ]; then "$VISUAL" "$path" && return 0; fi
  if [ -n "${EDITOR:-}" ]; then "$EDITOR" "$path" && return 0; fi
  if command -v code >/dev/null 2>&1; then code -w "$path" && return 0; fi
  if command -v code-insiders >/dev/null 2>&1; then code-insiders -w "$path" && return 0; fi
  if command -v gedit >/dev/null 2>&1; then gedit --wait "$path" && return 0; fi
  if command -v vim >/dev/null 2>&1; then vim "$path" && return 0; fi
  if command -v nvim >/dev/null 2>&1; then nvim "$path" && return 0; fi
  if command -v nano >/dev/null 2>&1; then nano "$path" && return 0; fi
  if command -v subl >/dev/null 2>&1; then subl -w "$path" && return 0; fi
  if command -v open >/dev/null 2>&1; then open "$path" && return 0; fi
  if command -v xdg-open >/dev/null 2>&1; then xdg-open "$path" && return 0; fi
  _cu_warn "请手动打开：$path"
}

_cu_load_env() {
  local file="$1"

  # 立即保存PATH - 在任何操作之前
  local saved_path="$PATH"
  local saved_home="$HOME"
  local saved_shell="$SHELL"
  local saved_user="$USER"
  local saved_logname="$LOGNAME"

  if [ ! -f "$file" ]; then
    _cu_err "未找到环境文件：$file"
    return 1
  fi

  # 安全地清理 ANTHROPIC_ 开头的环境变量
  local var
  for var in $(compgen -v | command grep '^ANTHROPIC_' 2>/dev/null || true); do
    unset "$var" 2>/dev/null || true
  done

  # 使用临时变量读取 .env 文件，避免 set -a 的副作用
  local line key value
  while IFS= read -r line || [ -n "$line" ]; do
    # 跳过注释和空行
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue

    # 解析 export 语句
    if [[ "$line" =~ ^[[:space:]]*export[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"

      # 移除引号
      value="${value%\"}"
      value="${value#\"}"
      value="${value%\'}"
      value="${value#\'}"

      # 只导出 ANTHROPIC_ 开头的变量
      if [[ "$key" == ANTHROPIC_* ]]; then
        export "$key=$value" 2>/dev/null || true
      fi
    fi
  done < "$file"

  # 强制恢复关键环境变量 - 确保即使上面失败也会执行
  export PATH="$saved_path"
  export HOME="$saved_home"
  export SHELL="$saved_shell"
  export USER="$saved_user"
  export LOGNAME="$saved_logname"

  return 0
}

_cu_show() {
  if [ -f "$CLAUDE_USE_LAST" ]; then
    _cu_info "已记忆默认环境：$(<"$CLAUDE_USE_LAST")"
  else
    _cu_info "暂无已记忆默认环境。"
  fi
  printf '当前生效变量：\n'
  printf '  %-28s = %s\n' ANTHROPIC_BASE_URL "${ANTHROPIC_BASE_URL:-<未设置>}"
  printf '  %-28s = %s\n' ANTHROPIC_AUTH_TOKEN "${ANTHROPIC_AUTH_TOKEN:+<已设置>}"
  printf '  %-28s = %s\n' ANTHROPIC_MODEL "${ANTHROPIC_MODEL:-<未设置>}"
  printf '  %-28s = %s\n' ANTHROPIC_SMALL_FAST_MODEL "${ANTHROPIC_SMALL_FAST_MODEL:-<未设置>}"
}

_cu_cmd_list() {
  _cu_ensure_envdir
  local saved=""
  [ -f "$CLAUDE_USE_LAST" ] && saved="$(<"$CLAUDE_USE_LAST")"
  mapfile -t names < <(_cu_list_names)
  printf '可用环境配置（%s）：\n' "$CLAUDE_USE_ENV_DIR"
  if [ ${#names[@]} -eq 0 ]; then
    printf '  （空）可添加 *.env 文件\n'
    return 0
  fi
  local n
  for n in "${names[@]}"; do
    if [ -n "$saved" ] && [ "$n" = "$saved" ]; then
      printf '  * %s  (默认)\n' "$n"
    else
      printf '    %s\n' "$n"
    fi
  done
}

_cu_cmd_switch() {
  local name="$1"
  [ -z "$name" ] && { _cu_err "用法：claude-switch use <name>"; return 2; }
  [[ "$name" == *.env ]] || name="$name.env"
  local file="$CLAUDE_USE_ENV_DIR/$name"
  if _cu_with_spinner "加载环境..." _cu_load_env "$file"; then
    printf '%s\n' "${name%.env}" > "$CLAUDE_USE_LAST"
    _cu_sync_claude_settings
    _cu_ok "已切换到环境：${name%.env}（已保存为默认）"
    _cu_show
  else
    return 1
  fi
}

_cu_template() {
  cat <<'T'
# 示例模板：请按需修改
export ANTHROPIC_BASE_URL=""
export ANTHROPIC_AUTH_TOKEN=""
export ANTHROPIC_MODEL=""
export ANTHROPIC_SMALL_FAST_MODEL=""
T
}

_cu_cmd_new() {
  local name="$1"
  [ -z "$name" ] && { _cu_err "用法：claude-switch new <name>"; return 2; }
  _cu_ensure_envdir
  [[ "$name" == *.env ]] || name="$name.env"
  local file="$CLAUDE_USE_ENV_DIR/$name"
  if [ -f "$file" ]; then
    _cu_err "已存在：$file"
    return 1
  fi
  _cu_template > "$file"
  _cu_ok "已创建：$file"
  _cu_open_path "$file"
}

_cu_cmd_edit() {
  local name="$1"
  [ -z "$name" ] && { _cu_err "用法：claude-switch edit <name>"; return 2; }
  _cu_ensure_envdir
  [[ "$name" == *.env ]] || name="$name.env"
  local file="$CLAUDE_USE_ENV_DIR/$name"
  if [ ! -f "$file" ]; then
    _cu_template > "$file"
    _cu_info "不存在，已创建模板：$file"
  fi
  _cu_open_path "$file"
}

_cu_cmd_del() {
  local name="$1"
  [ -z "$name" ] && { _cu_err "用法：claude-switch del <name>"; return 2; }
  _cu_ensure_envdir
  [[ "$name" == *.env ]] || name="$name.env"
  local file="$CLAUDE_USE_ENV_DIR/$name"
  if [ ! -f "$file" ]; then
    _cu_err "未找到：$file"
    return 1
  fi
  printf '确认删除 %s ? 输入 yes 以继续：' "${name%.env}"
  local answer; read -r answer
  if [ "$answer" = "yes" ]; then
    rm -f -- "$file"
    _cu_ok "已删除：$file"
    if [ -f "$CLAUDE_USE_LAST" ] && [ "$(<"$CLAUDE_USE_LAST")" = "${name%.env}" ]; then
      rm -f -- "$CLAUDE_USE_LAST"
      _cu_info "已清理默认记忆。"
    fi
  else
    _cu_info "已取消。"
  fi
}

_cu_help() {
  cat <<H
用法：
  claude-switch list                 列出全部环境
  claude-switch use <name>           切换到 <name> 环境（无需 .env 后缀）
  claude-switch new <name>           新建 <name>.env，并打开编辑器
  claude-switch edit <name>          编辑 <name>.env（不存在则创建模板）
  claude-switch del <name>           删除 <name>.env（需输入 yes 确认）
  claude-switch show|current         显示已记忆的默认与当前变量
  claude-switch open|dir             打开环境目录
  claude-switch help                 显示本帮助

目录：
  环境目录：$CLAUDE_USE_ENV_DIR
  记忆文件：$CLAUDE_USE_LAST

配置：
  CLAUDE_CODE_HOME        默认 $HOME/.claude
  CLAUDE_USE_EDITOR_CMD   自定义编辑命令（优先级最高）
H
}

claude-switch() {
  local cmd="${1:-}"; shift 2>/dev/null || true
  case "$cmd" in
    ""|help|-h|--help)   _cu_help ;;
    list|ls)             _cu_cmd_list ;;
    use)                 _cu_cmd_switch "$1" ;;
    new)                 _cu_cmd_new "$@" ;;
    edit)                _cu_cmd_edit "$@" ;;
    del|delete|rm)       _cu_cmd_del "$@" ;;
    show|current)        _cu_show ;;
    open|dir)            _cu_open_path "$CLAUDE_USE_ENV_DIR" ;;
    *)                   _cu_err "未知命令：$cmd"; _cu_info "请使用 'claude-switch use <name>' 切换环境，或运行 'claude-switch help' 查看帮助"; return 2 ;;
  esac
}

_cu_autoload_on_startup() {
  _cu_ensure_envdir
  local chosen=""
  if [ -f "$CLAUDE_USE_LAST" ]; then
    chosen="$(<"$CLAUDE_USE_LAST")"
  else
    mapfile -t names < <(_cu_list_names)
    if [ ${#names[@]} -gt 0 ]; then
      chosen="${names[0]}"
    fi
  fi
  if [ -n "$chosen" ]; then
    [[ "$chosen" == *.env ]] || chosen="$chosen.env"
    local file="$CLAUDE_USE_ENV_DIR/$chosen"
    _cu_load_env "$file" >/dev/null 2>&1 || true
  fi
}

if [[ $- == *i* ]]; then
  _cu_autoload_on_startup
fi
