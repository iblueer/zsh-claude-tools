# bin/claude-use.zsh
# Claude Code API 环境管理工具（Zsh）
# 配置项：
#   CLAUDE_CODE_HOME        默认 $HOME/.claude   => 环境目录位于 $CLAUDE_CODE_HOME/envs
#   CLAUDE_USE_EDITOR_CMD   覆盖编辑器命令（优先级最高），例如：export CLAUDE_USE_EDITOR_CMD="code -w"

: ${CLAUDE_CODE_HOME:="$HOME/.claude"}
typeset -g CLAUDE_USE_ENV_DIR="$CLAUDE_CODE_HOME/envs"
typeset -g CLAUDE_USE_LAST="$CLAUDE_USE_ENV_DIR/last_choice"

_cu_info() { print -r -- "▸ $*"; }
_cu_warn() { print -r -- "⚠ $*"; }
_cu_err()  { print -r -- "✗ $*"; }
_cu_ok()   { print -r -- "✓ $*"; }

_cu_ensure_envdir() { [[ -d "$CLAUDE_USE_ENV_DIR" ]] || mkdir -p "$CLAUDE_USE_ENV_DIR"; }

_cu_list_names() {
  _cu_ensure_envdir
  local f
  for f in "$CLAUDE_USE_ENV_DIR"/*.env(N); do
    print -r -- "${f:t:r}"
  done
}

_cu_open_path() {
  local path="$1"
  if [[ -n "${CLAUDE_USE_EDITOR_CMD:-}" ]]; then
    eval "$CLAUDE_USE_EDITOR_CMD ${(q)path}"
    return $?
  fi
  if [[ -n "${VISUAL:-}" ]]; then "$VISUAL" "$path" && return 0; fi
  if [[ -n "${EDITOR:-}" ]]; then "$EDITOR" "$path" && return 0; fi
  if command -v code >/dev/null 2>&1; then code -w "$path" && return 0; fi
  if command -v subl >/dev/null 2>&1; then subl -w "$path" && return 0; fi
  if command -v nano >/dev/null 2>&1; then nano "$path" && return 0; fi
  if command -v vim  >/dev/null 2>&1; then vim  "$path" && return 0; fi
  if command -v open >/dev/null 2>&1; then open "$path" && return 0; fi
  if command -v xdg-open >/dev/null 2>&1; then xdg-open "$path" && return 0; fi
  _cu_warn "请手动打开：$path"
}

_cu_load_env() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    _cu_err "未找到环境文件：$file"
    return 1
  fi
  unset -m 'ANTHROPIC_*'
  set -a
  source "$file"
  set +a
}

_cu_show() {
  if [[ -f "$CLAUDE_USE_LAST" ]]; then
    _cu_info "已记忆默认环境：$(<"$CLAUDE_USE_LAST")"
  else
    _cu_info "暂无已记忆默认环境。"
  fi
  print -r -- "当前生效变量："
  printf '  %-28s = %s\n' ANTHROPIC_BASE_URL "${ANTHROPIC_BASE_URL:-<未设置>}"
  printf '  %-28s = %s\n' ANTHROPIC_AUTH_TOKEN "${ANTHROPIC_AUTH_TOKEN:+<已设置>}"
  printf '  %-28s = %s\n' ANTHROPIC_MODEL "${ANTHROPIC_MODEL:-<未设置>}"
  printf '  %-28s = %s\n' ANTHROPIC_SMALL_FAST_MODEL "${ANTHROPIC_SMALL_FAST_MODEL:-<未设置>}"
}

_cu_cmd_list() {
  _cu_ensure_envdir
  local saved=""
  [[ -f "$CLAUDE_USE_LAST" ]] && saved="$(<"$CLAUDE_USE_LAST")"
  local names=() n
  names=($(_cu_list_names))
  print -r -- "可用环境配置（$CLAUDE_USE_ENV_DIR）："
  if (( ${#names} == 0 )); then
    print -r -- "  （空）可添加 *.env 文件"
    return 0
  fi
  for n in "${names[@]}"; do
    if [[ -n "$saved" && "$n" == "$saved" ]]; then
      print -r -- "  * $n  (默认)"
    else
      print -r -- "    $n"
    fi
  done
}

_cu_cmd_switch() {
  local name="$1"
  [[ -z "$name" ]] && { _cu_err "用法：claude-use <name>"; return 2; }
  [[ "$name" == *.env ]] || name="$name.env"
  local file="$CLAUDE_USE_ENV_DIR/$name"
  if _cu_load_env "$file"; then
    print -r -- "${name%.env}" > "$CLAUDE_USE_LAST"
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
  [[ -z "$name" ]] && { _cu_err "用法：claude-use new <name>"; return 2; }
  _cu_ensure_envdir
  [[ "$name" == *.env ]] || name="$name.env"
  local file="$CLAUDE_USE_ENV_DIR/$name"
  if [[ -f "$file" ]]; then
    _cu_err "已存在：$file"
    return 1
  fi
  _cu_template > "$file"
  _cu_ok "已创建：$file"
  _cu_open_path "$file"
}

_cu_cmd_edit() {
  local name="$1"
  [[ -z "$name" ]] && { _cu_err "用法：claude-use edit <name>"; return 2; }
  _cu_ensure_envdir
  [[ "$name" == *.env ]] || name="$name.env"
  local file="$CLAUDE_USE_ENV_DIR/$name"
  if [[ ! -f "$file" ]]; then
    _cu_template > "$file"
    _cu_info "不存在，已创建模板：$file"
  fi
  _cu_open_path "$file"
}

_cu_cmd_del() {
  local name="$1"
  [[ -z "$name" ]] && { _cu_err "用法：claude-use del <name>"; return 2; }
  _cu_ensure_envdir
  [[ "$name" == *.env ]] || name="$name.env"
  local file="$CLAUDE_USE_ENV_DIR/$name"
  if [[ ! -f "$file" ]]; then
    _cu_err "未找到：$file"
    return 1
  fi
  print -n -- "确认删除 ${name%.env} ? 输入 yes 以继续："
  local answer; read -r answer
  if [[ "$answer" == "yes" ]]; then
    rm -f -- "$file"
    _cu_ok "已删除：$file"
    if [[ -f "$CLAUDE_USE_LAST" && "$( <"$CLAUDE_USE_LAST")" == "${name%.env}" ]]; then
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
  claude-use list                 列出全部环境
  claude-use <name>               切换到 <name> 环境（无需 .env 后缀）
  claude-use new <name>           新建 <name>.env，并打开编辑器
  claude-use edit <name>          编辑 <name>.env（不存在则创建模板）
  claude-use del <name>           删除 <name>.env（需输入 yes 确认）
  claude-use show|current         显示已记忆的默认与当前变量
  claude-use open|dir             打开环境目录
  claude-use help                 显示本帮助

目录：
  环境目录：$CLAUDE_USE_ENV_DIR
  记忆文件：$CLAUDE_USE_LAST

配置：
  CLAUDE_CODE_HOME        默认 $HOME/.claude
  CLAUDE_USE_EDITOR_CMD   自定义编辑命令（优先级最高）
H
}

claude-use() {
  local cmd="${1:-}"; shift 2>/dev/null || true
  case "$cmd" in
    ""|help|-h|--help)   _cu_help ;;
    list|ls)             _cu_cmd_list ;;
    new)                 _cu_cmd_new "$@" ;;
    edit)                _cu_cmd_edit "$@" ;;
    del|delete|rm)       _cu_cmd_del "$@" ;;
    show|current)        _cu_show ;;
    open|dir)            _cu_open_path "$CLAUDE_USE_ENV_DIR" ;;
    *)                   _cu_cmd_switch "$cmd" ;;
  esac
}

_cu_autoload_on_startup() {
  _cu_ensure_envdir
  local chosen=""
  if [[ -f "$CLAUDE_USE_LAST" ]]; then
    chosen="$(<"$CLAUDE_USE_LAST")"
  else
    local names=($(_cu_list_names))
    if (( ${#names} > 0 )); then
      chosen="${names[1]}"
    fi
  fi
  if [[ -n "$chosen" ]]; then
    _cu_cmd_switch "$chosen" >/dev/null 2>&1 || true
  fi
}

if [[ -o interactive ]]; then
  _cu_autoload_on_startup
fi

claude-which() { claude-use show; }
