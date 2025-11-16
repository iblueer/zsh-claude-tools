#!/usr/bin/env zsh
# bin/claude-switch.zsh
# Claude Code API 环境管理工具（Zsh）
# 配置项：
#   CLAUDE_CODE_HOME        默认 $HOME/.claude   => 环境目录位于 $CLAUDE_CODE_HOME/envs
#   CLAUDE_USE_EDITOR_CMD   覆盖编辑器命令（优先级最高），例如：export CLAUDE_USE_EDITOR_CMD="code -w"

: ${CLAUDE_CODE_HOME:="$HOME/.claude"}
typeset -g CLAUDE_USE_ENV_DIR="$CLAUDE_CODE_HOME/envs"
typeset -g CLAUDE_USE_LAST="$CLAUDE_USE_ENV_DIR/last_choice"
typeset -ga CLAUDE_SWITCH_SUBCOMMANDS=(help list ls use new edit del show open)

_cu_info() { print -r -- "▸ $*"; }
_cu_warn() { print -r -- "⚠ $*"; }
_cu_err()  { print -r -- "✗ $*"; }
_cu_ok()   { print -r -- "✓ $*"; }

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
  print -n -- "$msg "
  {
    local -a frames=('|' '/' '-' $'\\')
    local i=1
    while :; do
      printf "\r%s %s" "$msg" "${frames[i]}"
      i=$(( i % ${#frames} + 1 ))
      sleep 0.1
    done
  } &!
  local spid=$!
  "$@"
  local ret=$?
  kill $spid 2>/dev/null
  wait $spid 2>/dev/null || true
  printf "\r%s\n" "$msg"
  return $ret
}

_cu_ensure_envdir() { [[ -d "$CLAUDE_USE_ENV_DIR" ]] || mkdir -p "$CLAUDE_USE_ENV_DIR"; }

_cu_list_names() {
  _cu_ensure_envdir
  local f
  for f in "$CLAUDE_USE_ENV_DIR"/*.env(N); do
    print -r -- "${f:t:r}"
  done
}

_cu_env_candidates() {
  local cur="${1:-}"
  local prefix suffix search_dir entry base rel
  reply=()
  if [[ "$cur" == */* ]]; then
    prefix="${cur%/*}"
    suffix="${cur##*/}"
    search_dir="$CLAUDE_USE_ENV_DIR/$prefix"
  else
    prefix=""
    suffix="$cur"
    search_dir="$CLAUDE_USE_ENV_DIR"
  fi
  [[ -d "$search_dir" ]] || return
  local -a entries=()
  if command -v find >/dev/null 2>&1; then
    while IFS= read -r entry; do
      base="${entry##*/}"
      [[ "$base" == "$suffix"* ]] || continue
      if [[ -d "$entry" ]]; then
        rel="${prefix:+$prefix/}$base/"
      elif [[ "$entry" == *.env ]]; then
        rel="${prefix:+$prefix/}${base%.env}"
      else
        continue
      fi
      entries+=("$rel")
    done < <(LC_ALL=C find "$search_dir" -mindepth 1 -maxdepth 1 \( -type d -o -type f -name '*.env' \) -print 2>/dev/null | LC_ALL=C sort)
  else
    for entry in "$search_dir"/*; do
      [[ -e "$entry" ]] || continue
      base="${entry##*/}"
      [[ "$base" == "$suffix"* ]] || continue
      if [[ -d "$entry" ]]; then
        rel="${prefix:+$prefix/}$base/"
      elif [[ "$entry" == *.env ]]; then
        rel="${prefix:+$prefix/}${base%.env}"
      else
        continue
      fi
      entries+=("$rel")
    done
  fi
  (( ${#entries[@]} > 0 )) && reply=(${(ou)entries})
}

_cu_open_path() {
  local file_path="$1"
  
  # 调试信息
  # echo "DEBUG: 尝试打开路径: $file_path"
  # echo "DEBUG: code 命令: $(command -v code 2>/dev/null || echo '不可用')"
  # echo "DEBUG: PATH: $PATH"
  
  if _cu_is_windows; then
    local winpath="$file_path"
    if command -v cygpath >/dev/null 2>&1; then
      winpath="$(cygpath -w "$file_path")"
    fi
    if [[ -d "$file_path" ]]; then
      if command -v code >/dev/null 2>&1; then code -w "$winpath" && return 0; fi
      if command -v explorer.exe >/dev/null 2>&1; then explorer.exe "$winpath" && return 0; fi
    else
      if command -v code >/dev/null 2>&1; then code -w "$winpath" && return 0; fi
      if command -v notepad.exe >/dev/null 2>&1; then notepad.exe "$winpath" && return 0; fi
    fi
    if command -v cmd.exe >/dev/null 2>&1; then
      cmd.exe /c start "" "$winpath" >/dev/null 2>&1 && return 0
    fi
    _cu_warn "请手动打开：$file_path"
    return 0
  fi
  if [[ -n "${CLAUDE_USE_EDITOR_CMD:-}" ]]; then
    # Try custom editor command; fall back if it fails
    if eval "$CLAUDE_USE_EDITOR_CMD ${(q)file_path}"; then
      return 0
    else
      _cu_warn "自定义编辑器命令失败：$CLAUDE_USE_EDITOR_CMD"
    fi
  fi
  # Directory vs file: choose sensible openers
  if [[ -d "$file_path" ]]; then
    # Prefer project-oriented openers for directories
    if command -v code  >/dev/null 2>&1; then code  -w "$file_path" && return 0; fi
    if command -v code-insiders >/dev/null 2>&1; then code-insiders -w "$file_path" && return 0; fi
    if command -v subl  >/dev/null 2>&1; then subl -w "$file_path" && return 0; fi
    if command -v xdg-open >/dev/null 2>&1; then xdg-open "$file_path" && return 0; fi
    # Fall back to environment/editor hints
    if [[ -n "${VISUAL:-}" ]]; then
      local -a _cu_cmd
      _cu_cmd=("${(z)VISUAL}")
      "${_cu_cmd[@]}" "$file_path" && return 0
    fi
    if [[ -n "${EDITOR:-}" ]]; then
      local -a _cu_cmd
      _cu_cmd=("${(z)EDITOR}")
      "${_cu_cmd[@]}" "$file_path" && return 0
    fi
    if command -v vim   >/dev/null 2>&1; then vim   "$file_path" && return 0; fi
    if command -v nvim  >/dev/null 2>&1; then nvim  "$file_path" && return 0; fi
    _cu_warn "请手动打开：$file_path"
    return 0
  fi
  # Respect common env editor hints first
  if [[ -n "${VISUAL:-}" ]]; then
    local -a _cu_cmd
    _cu_cmd=("${(z)VISUAL}")
    "${_cu_cmd[@]}" "$file_path" && return 0
  fi
  if [[ -n "${EDITOR:-}" ]]; then
    local -a _cu_cmd
    _cu_cmd=("${(z)EDITOR}")
    "${_cu_cmd[@]}" "$file_path" && return 0
  fi
  # Prefer advanced GUI editors that support waiting
  if command -v code  >/dev/null 2>&1; then code  -w "$file_path" && return 0; fi
  if command -v code-insiders >/dev/null 2>&1; then code-insiders -w "$file_path" && return 0; fi
  if command -v gedit >/dev/null 2>&1; then gedit --wait "$file_path" && return 0; fi
  # Terminal editors
  if command -v vim   >/dev/null 2>&1; then vim   "$file_path" && return 0; fi
  if command -v nvim  >/dev/null 2>&1; then nvim  "$file_path" && return 0; fi
  if command -v nano  >/dev/null 2>&1; then nano  "$file_path" && return 0; fi
  # Other GUI editors/openers as fallback
  if command -v subl  >/dev/null 2>&1; then subl -w "$file_path" && return 0; fi
  if command -v open  >/dev/null 2>&1; then open  "$file_path" && return 0; fi
  if command -v xdg-open >/dev/null 2>&1; then xdg-open "$file_path" && return 0; fi
  _cu_warn "请手动打开：$file_path"
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
  if _cu_with_spinner "加载环境..." _cu_load_env "$file"; then
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
  claude-switch list                 列出全部环境
  claude-switch use <name>           切换到 <name> 环境（无需 .env 后缀）
  claude-switch <name>               切换到 <name> 环境（兼容旧用法）
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
    del)                 _cu_cmd_del "$@" ;;
    show)                _cu_show ;;
    open)                _cu_open_path "$CLAUDE_USE_ENV_DIR" ;;
    *)                   _cu_cmd_switch "$cmd" ;;
  esac
}

_cu_zsh_complete() {
  local cur="${words[CURRENT]}"
  local -a envs
  _cu_env_candidates "$cur"
  envs=("${reply[@]}")
  if (( CURRENT == 2 )); then
    if [[ "$cur" != */* ]]; then
      (( ${#CLAUDE_SWITCH_SUBCOMMANDS[@]} > 0 )) && compadd -a CLAUDE_SWITCH_SUBCOMMANDS
    fi
    (( ${#envs[@]} > 0 )) && compadd -Q -S '' -a envs
    return
  fi
  case "${words[2]}" in
    use|new|edit|del|delete|rm)
      (( ${#envs[@]} > 0 )) && compadd -Q -S '' -a envs
      ;;
  esac
}

_cu_setup_completion() {
  if (( $+functions[compdef] )); then
    compdef _cu_zsh_complete claude-switch
  fi
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
  _cu_setup_completion
  _cu_autoload_on_startup
fi
