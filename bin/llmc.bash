#!/usr/bin/env bash
# bin/llmc.bash
# LLMC - LLM Config Manager (Interactive TUI for claude-switch)
# 交互式环境选择器（Bash）

: "${CLAUDE_CODE_HOME:="$HOME/.claude"}"
LLMC_ENV_DIR="$CLAUDE_CODE_HOME/envs"
LLMC_STARS_FILE="$CLAUDE_CODE_HOME/stars"
LLMC_LAST_FILE="$LLMC_ENV_DIR/last_choice"

# 工具函数
_llmc_info() { printf '▸ %s\n' "$*"; }
_llmc_warn() { printf '⚠ %s\n' "$*"; }
_llmc_err()  { printf '✗ %s\n' "$*"; }
_llmc_ok()   { printf '✓ %s\n' "$*"; }

_llmc_switch_cmd() {
  if command -v claude-switch >/dev/null 2>&1; then
    printf '%s\n' "claude-switch"
    return 0
  fi
  if command -v llm-switch >/dev/null 2>&1; then
    printf '%s\n' "llm-switch"
    return 0
  fi
  return 1
}

_llmc_forward() {
  local subcmd="$1"; shift || true
  local switch_cmd
  switch_cmd="$(_llmc_switch_cmd)" || { _llmc_err "未找到 claude-switch/llm-switch 命令"; return 127; }
  "$switch_cmd" "$subcmd" "$@"
}

# 确保目录存在
_llmc_ensure_dirs() {
  [ -d "$LLMC_ENV_DIR" ] || mkdir -p "$LLMC_ENV_DIR"
  [ -f "$LLMC_STARS_FILE" ] || touch "$LLMC_STARS_FILE"
}

# 获取当前生效的环境名
_llmc_get_current() {
  if [ -f "$LLMC_LAST_FILE" ]; then
    cat "$LLMC_LAST_FILE"
  fi
}

# 星标管理
_llmc_is_starred() {
  local name="$1"
  [ -f "$LLMC_STARS_FILE" ] && grep -Fxq "$name" "$LLMC_STARS_FILE"
}

_llmc_add_star() {
  local name="$1"
  _llmc_ensure_dirs
  if ! _llmc_is_starred "$name"; then
    printf '%s\n' "$name" >> "$LLMC_STARS_FILE"
    _llmc_ok "已添加星标：$name"
  else
    _llmc_info "已经是星标：$name"
  fi
}

_llmc_remove_star() {
  local name="$1"
  if _llmc_is_starred "$name"; then
    if [ -f "$LLMC_STARS_FILE" ]; then
      local temp_file
      temp_file="$(mktemp)"
      grep -Fxv "$name" "$LLMC_STARS_FILE" > "$temp_file"
      mv "$temp_file" "$LLMC_STARS_FILE"
      _llmc_ok "已移除星标：$name"
    fi
  else
    _llmc_info "不是星标：$name"
  fi
}

_llmc_list_starred() {
  _llmc_ensure_dirs
  printf '星标环境：\n'
  if [ -s "$LLMC_STARS_FILE" ]; then
    while IFS= read -r line; do
      printf '  🌟 %s\n' "$line"
    done < "$LLMC_STARS_FILE"
  else
    printf '  （无）\n'
  fi
}

# 扫描所有环境文件和目录
# 返回格式：type|path|display_name
# type: dir|env
_llmc_scan_items() {
  local search_dir="${1:-$LLMC_ENV_DIR}"
  local prefix="${2:-}"
  local entry base rel type

  # 扫描当前目录
  for entry in "$search_dir"/*; do
    [ -e "$entry" ] || continue
    base="${entry##*/}"

    if [ -d "$entry" ]; then
      type="dir"
      rel="${prefix:+$prefix/}$base"
      printf '%s|%s|%s/\n' "$type" "$entry" "$rel"
    elif [[ "$entry" == *.env ]]; then
      type="env"
      rel="${prefix:+$prefix/}${base%.env}"
      printf '%s|%s|%s\n' "$type" "$entry" "$rel"
    fi
  done | LC_ALL=C sort
}

# 读取单个字符（支持特殊键）
_llmc_read_key() {
  local key
  IFS= read -rsn1 key

  # 处理方向键（ANSI转义序列）
  if [ "$key" = $'\e' ]; then
    read -rsn1 -t 0.01 key
    if [ "$key" = "[" ]; then
      read -rsn1 key
      case "$key" in
        A) echo "up"; return ;;
        B) echo "down"; return ;;
        C) echo "right"; return ;;
        D) echo "left"; return ;;
      esac
    fi
    echo "esc"
    return
  fi

  echo "$key"
}

# 交互式选择器主函数
_llmc_interactive() {
  _llmc_ensure_dirs

  local current_dir="$LLMC_ENV_DIR"
  local current_prefix=""
  local cursor=0
  local current_env
  current_env="$(_llmc_get_current)"

  # 隐藏光标
  printf '\e[?25l'

  # 清屏并显示标题
  clear

  while true; do
    # 扫描当前目录
    local -a items=()
    local -a display_items=()
    local type path display

    while IFS='|' read -r type path display; do
      items+=("$type|$path|$display")

      # 构建显示文本
      local prefix_icon=""
      local suffix_mark=""

      if [ "$type" = "dir" ]; then
        prefix_icon="📁"
      else
        # 检查是否是当前环境
        if [ -n "$current_env" ] && [ "$display" = "$current_env" ]; then
          prefix_icon="💡"
        else
          prefix_icon="  "
        fi

        # 检查是否有星标
        if _llmc_is_starred "$display"; then
          suffix_mark=" 🌟"
        fi
      fi

      display_items+=("$prefix_icon $display$suffix_mark")
    done < <(_llmc_scan_items "$current_dir" "$current_prefix")

    # 如果不在根目录，添加 ".." 返回项
    if [ "$current_dir" != "$LLMC_ENV_DIR" ]; then
      items=("dir|../..|.." "${items[@]}")
      display_items=("📂 .." "${display_items[@]}")
    fi

    # 检查是否有项目
    if [ ${#items[@]} -eq 0 ]; then
      printf '当前目录为空：%s\n' "$current_dir"
      printf '按 q 退出\n'
      key="$(_llmc_read_key)"
      if [ "$key" = "q" ] || [ "$key" = "esc" ]; then
        break
      fi
      continue
    fi

    # 确保光标在有效范围内
    (( cursor < 0 )) && cursor=0
    (( cursor >= ${#items[@]} )) && cursor=$((${#items[@]} - 1))

    # 清屏并重新绘制
    clear
    printf '╔═══════════════════════════════════════════════════════════╗\n'
    printf '║  LLMC - 环境选择器                                         ║\n'
    printf '║  当前: %-51s ║\n' "${current_prefix:-/}"
    printf '╠═══════════════════════════════════════════════════════════╣\n'
    printf '║  ↑/k:上  ↓/j:下  ←/h:返回  →/l/Enter:选择  Space:星标  q:退出 ║\n'
    printf '╚═══════════════════════════════════════════════════════════╝\n'
    printf '\n'

    # 显示列表
    local i
    for i in "${!items[@]}"; do
      if [ "$i" -eq "$cursor" ]; then
        printf '  ▶ %s\n' "${display_items[i]}"
      else
        printf '    %s\n' "${display_items[i]}"
      fi
    done

    # 读取按键
    local key
    key="$(_llmc_read_key)"

    case "$key" in
      k|up)
        (( cursor > 0 )) && (( cursor-- ))
        ;;
      j|down)
        (( cursor < ${#items[@]} - 1 )) && (( cursor++ ))
        ;;
      h|left)
        # 返回上级目录
        if [ "$current_dir" != "$LLMC_ENV_DIR" ]; then
          current_dir="${current_dir%/*}"
          [ -z "$current_dir" ] && current_dir="$LLMC_ENV_DIR"
          current_prefix="${current_prefix%/*}"
          cursor=0
        fi
        ;;
      l|right|'')
        # 选择/进入 (空字符串表示Enter键)
        local selected="${items[cursor]}"
        local sel_type="${selected%%|*}"
        local sel_path="${selected#*|}"; sel_path="${sel_path%%|*}"
        local sel_display="${selected##*|}"

        if [ "$sel_type" = "dir" ]; then
          if [ "$sel_display" = ".." ]; then
            # 返回上级
            current_dir="${current_dir%/*}"
            [ -z "$current_dir" ] && current_dir="$LLMC_ENV_DIR"
            current_prefix="${current_prefix%/*}"
          else
            # 进入子目录
            current_dir="$sel_path"
            current_prefix="${sel_display%/}"
          fi
          cursor=0
        else
          # 选择环境
          clear
          printf '\e[?25h'  # 恢复光标

          _llmc_forward use "$sel_display"
          return 0
        fi
        ;;
      ' '|$'\t')
        # 切换星标
        local selected="${items[cursor]}"
        local sel_type="${selected%%|*}"
        local sel_display="${selected##*|}"

        if [ "$sel_type" = "env" ]; then
          if _llmc_is_starred "$sel_display"; then
            _llmc_remove_star "$sel_display"
          else
            _llmc_add_star "$sel_display"
          fi
          sleep 0.3  # 短暂暂停以显示提示信息
        fi
        ;;
      q|esc)
        break
        ;;
    esac
  done

  # 恢复光标并清屏
  clear
  printf '\e[?25h'
  _llmc_info "已退出"
}

# 命令行接口
llmc() {
  local cmd="${1:-interactive}"

  case "$cmd" in
    ""|interactive|i)
      _llmc_interactive
      ;;
    use|show|open|new|edit|del)
      shift
      _llmc_forward "$cmd" "$@"
      ;;
    list|ls)
      _llmc_ensure_dirs
      local current_env
      current_env="$(_llmc_get_current)"
      printf '可用环境（星标优先）：\n'

      # 先显示星标项
      if [ -s "$LLMC_STARS_FILE" ]; then
        while IFS= read -r name; do
          local marker="  "
          [ -n "$current_env" ] && [ "$name" = "$current_env" ] && marker="💡"
          printf '  %s 🌟 %s\n' "$marker" "$name"
        done < "$LLMC_STARS_FILE"
      fi

      # 显示非星标项
      _llmc_scan_items | while IFS='|' read -r type path display; do
        [ "$type" != "env" ] && continue
        _llmc_is_starred "$display" && continue

        local marker="  "
        [ -n "$current_env" ] && [ "$display" = "$current_env" ] && marker="💡"
        printf '  %s    %s\n' "$marker" "$display"
      done
      ;;
    star)
      shift
      [ -z "$1" ] && { _llmc_err "用法：llmc star <name>"; return 2; }
      _llmc_add_star "$1"
      ;;
    unstar)
      shift
      [ -z "$1" ] && { _llmc_err "用法：llmc unstar <name>"; return 2; }
      _llmc_remove_star "$1"
      ;;
    starred)
      _llmc_list_starred
      ;;
    help|--help|-h)
      cat <<'HELP'
用法：
  llmc                    启动交互式选择器
  llmc list               列出所有环境（星标优先）
  llmc use <name>         切换到 <name> 环境（同 claude-switch use）
  llmc show               显示默认记忆与当前变量（同 claude-switch show）
  llmc open               打开环境目录（同 claude-switch open）
  llmc new <name>         新建 <name>.env 并打开编辑器（同 claude-switch new）
  llmc edit <name>        编辑 <name>.env（同 claude-switch edit）
  llmc del <name>         删除 <name>.env（同 claude-switch del）
  llmc star <name>        添加星标
  llmc unstar <name>      移除星标
  llmc starred            列出所有星标项
  llmc help               显示帮助信息

交互式快捷键：
  ↑/k        向上移动
  ↓/j        向下移动
  ←/h        返回上级目录
  →/l/Enter  进入目录或选择环境
  Space/Tab  切换星标
  q/ESC      退出

HELP
      ;;
    *)
      # 尝试作为环境名直接切换（模糊匹配）
      local target="$cmd"
      local found=""

      # 查找匹配的环境
      while IFS='|' read -r type path display; do
        [ "$type" != "env" ] && continue
        if [[ "$display" == *"$target"* ]]; then
          found="$display"
          break
        fi
      done < <(_llmc_scan_items)

      if [ -n "$found" ]; then
        _llmc_forward use "$found" || return $?
      else
        _llmc_err "未找到匹配的环境：$target"
        _llmc_info "运行 'llmc list' 查看可用环境"
        return 1
      fi
      ;;
  esac
}

# 将 llmc 注册为 claude-switch 的子命令
if declare -f claude-switch >/dev/null 2>&1; then
  # 保存原始函数（通过重命名）
  eval "$(declare -f claude-switch | sed '1s/claude-switch/_claude_switch_orig/')"

  # 重新定义 claude-switch
  claude-switch() {
    if [ "$1" = "llmc" ]; then
      shift
      llmc "$@"
    else
      _claude_switch_orig "$@"
    fi
  }
fi
