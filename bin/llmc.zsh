#!/usr/bin/env zsh
# bin/llmc.zsh
# LLMC - LLM Config Manager (Interactive TUI for claude-switch)
# 交互式环境选择器（Zsh）

: ${CLAUDE_CODE_HOME:="$HOME/.claude"}
typeset -g LLMC_ENV_DIR="$CLAUDE_CODE_HOME/envs"
typeset -g LLMC_STARS_FILE="$CLAUDE_CODE_HOME/stars"
typeset -g LLMC_LAST_FILE="$LLMC_ENV_DIR/last_choice"

# 工具函数
_llmc_info() { print -r -- "▸ $*"; }
_llmc_warn() { print -r -- "⚠ $*"; }
_llmc_err()  { print -r -- "✗ $*"; }
_llmc_ok()   { print -r -- "✓ $*"; }

_llmc_switch_cmd() {
  if command -v claude-switch >/dev/null 2>&1; then
    print -r -- "claude-switch"
    return 0
  fi
  if command -v llm-switch >/dev/null 2>&1; then
    print -r -- "llm-switch"
    return 0
  fi
  return 1
}

_llmc_forward() {
  local subcmd="$1"; shift 2>/dev/null || true
  local switch_cmd
  switch_cmd="$(_llmc_switch_cmd)" || { _llmc_err "未找到 claude-switch/llm-switch 命令"; return 127; }
  "$switch_cmd" "$subcmd" "$@"
}

_llmc_tui_restore() {
  print -n "\e[2J\e[H"
  print -n "\e[?25h"
}

# 扫描整个 envs 目录树（用于“展开视图”）
# 返回格式：type|path|display_name|depth
_llmc_scan_tree() {
  local root="${1:-$LLMC_ENV_DIR}"
  local -a items=()
  local entry rel type depth

  if command -v find >/dev/null 2>&1; then
    while IFS= read -r entry; do
      [[ -e "$entry" ]] || continue
      rel="${entry#$root/}"
      [[ "$rel" == "$entry" ]] && continue

      if [[ -d "$entry" ]]; then
        type="dir"
        rel="${rel%/}/"
      elif [[ "$entry" == *.env ]]; then
        type="env"
        rel="${rel%.env}"
      else
        continue
      fi

      depth=0
      [[ "$rel" == */* ]] && depth=$(( ${#${(s:/:)rel}} - 1 ))
      items+=("$type|$entry|$rel|$depth")
    done < <(command find "$root" -mindepth 1 \( -type d -o -type f -name '*.env' \) -print 2>/dev/null | LC_ALL=C command sort)
  else
    # 降级：仅一层（无 find 时）
    local item_type item_path item_display
    while IFS='|' read -r item_type item_path item_display; do
      items+=("$item_type|$item_path|$item_display|0")
    done < <(_llmc_scan_items "$root" "")
  fi

  printf '%s\n' "${items[@]}"
}

# 确保目录存在
_llmc_ensure_dirs() {
  [[ -d "$LLMC_ENV_DIR" ]] || mkdir -p "$LLMC_ENV_DIR"
  [[ -f "$LLMC_STARS_FILE" ]] || touch "$LLMC_STARS_FILE"
}

# 获取当前生效的环境名
_llmc_get_current() {
  if [[ -f "$LLMC_LAST_FILE" ]]; then
    print -r -- "$(<"$LLMC_LAST_FILE")"
  fi
}

# 星标管理
_llmc_is_starred() {
  local name="$1"
  [[ -f "$LLMC_STARS_FILE" ]] && command grep -Fxq "$name" "$LLMC_STARS_FILE"
}

_llmc_add_star() {
  local name="$1"
  _llmc_ensure_dirs
  if ! _llmc_is_starred "$name"; then
    print -r -- "$name" >> "$LLMC_STARS_FILE"
    _llmc_ok "已添加星标：$name"
  else
    _llmc_info "已经是星标：$name"
  fi
}

_llmc_remove_star() {
  local name="$1"
  if _llmc_is_starred "$name"; then
    if [[ -f "$LLMC_STARS_FILE" ]]; then
      local temp_file="$(mktemp)"
      command grep -Fxv "$name" "$LLMC_STARS_FILE" > "$temp_file"
      mv "$temp_file" "$LLMC_STARS_FILE"
      _llmc_ok "已移除星标：$name"
    fi
  else
    _llmc_info "不是星标：$name"
  fi
}

_llmc_list_starred() {
  _llmc_ensure_dirs
  print -r -- "星标环境："
  if [[ -s "$LLMC_STARS_FILE" ]]; then
    cat "$LLMC_STARS_FILE" | while IFS= read -r line; do
      print -r -- "  🌟 $line"
    done
  else
    print -r -- "  （无）"
  fi
}

# 扫描所有环境文件和目录
# 返回格式：type|path|display_name
# type: dir|env
_llmc_scan_items() {
  local search_dir="${1:-$LLMC_ENV_DIR}"
  local prefix="${2:-}"
  local -a items=()
  local entry base rel type

  # 扫描当前目录
  for entry in "$search_dir"/*(N); do
    base="${entry##*/}"

    if [[ -d "$entry" ]]; then
      type="dir"
      rel="${prefix:+$prefix/}$base"
      items+=("$type|$entry|$rel/")
    elif [[ "$entry" == *.env ]]; then
      type="env"
      rel="${prefix:+$prefix/}${base%.env}"
      items+=("$type|$entry|$rel")
    fi
  done

  # 输出排序后的结果
  printf '%s\n' "${items[@]}" | LC_ALL=C command sort
}

# 读取单个字符（支持特殊键）
_llmc_read_key() {
  local key seq

  # 读取第一个字符
  read -rs -k 1 key

  # 检查是否是ESC序列的开始
  if [[ "$key" == $'\e' ]]; then
    # 尝试读取更多字符（非阻塞）
    read -rs -t 0.001 -k 2 seq 2>/dev/null

    # 解析ANSI转义序列
    case "$seq" in
      '[A') print "up"; return ;;
      '[B') print "down"; return ;;
      '[C') print "right"; return ;;
      '[D') print "left"; return ;;
      *) print "esc"; return ;;
    esac
  fi

  print "$key"
}

# 交互式选择器主函数
_llmc_interactive() {
  emulate -L zsh
  setopt localoptions localtraps
  unsetopt xtrace

  if [[ ! -t 0 || ! -t 1 ]]; then
    _llmc_err "交互模式需要 TTY，请在终端直接运行：llmc"
    return 2
  fi

  _llmc_ensure_dirs

  local current_dir="$LLMC_ENV_DIR"
  local current_prefix=""
  local -i cursor=1
  local current_env="$(_llmc_get_current)"
  local -a cursor_stack=()
  local -i tree_mode=1
  local want_jump_env=""
  local saved_dir="$current_dir"
  local saved_prefix="$current_prefix"
  local -i saved_cursor=$cursor
  local -a saved_stack=()

  # 启动时尽量把当前环境定位出来（目录层级较深时更友好）
  want_jump_env="$current_env"

  trap '_llmc_tui_restore; return 130' INT TERM
  trap '_llmc_tui_restore' EXIT

  _llmc_activate_current() {
    local selected="${items[cursor]}"
    local sel_type="${selected%%|*}"
    local sel_path="${selected#*|}"; sel_path="${sel_path%%|*}"
    local sel_display
    if (( tree_mode )); then
      sel_display="${selected#*|}"; sel_display="${sel_display#*|}"; sel_display="${sel_display%%|*}"
    else
      sel_display="${selected##*|}"
    fi

    if [[ "$sel_type" == "dir" ]]; then
      if (( tree_mode )); then
        tree_mode=0
        current_dir="$sel_path"
        current_prefix="${sel_display%/}"
        cursor=1
        cursor_stack=()
        return 1
      fi

      if [[ "$sel_display" == ".." ]]; then
        current_dir="${current_dir%/*}"
        [[ -z "$current_dir" ]] && current_dir="$LLMC_ENV_DIR"
        if [[ "$current_prefix" == */* ]]; then
          current_prefix="${current_prefix%/*}"
        else
          current_prefix=""
        fi
        if (( ${#cursor_stack} > 0 )); then
          cursor="${cursor_stack[-1]}"
          cursor_stack=("${cursor_stack[1,-2]}")
        else
          cursor=1
        fi
      else
        cursor_stack+=("$cursor")
        current_dir="$sel_path"
        current_prefix="${sel_display%/}"
        cursor=1
      fi
      return 1
    fi

    _llmc_tui_restore
    trap - INT TERM EXIT
    _llmc_forward use "$sel_display"
    return 0
  }

  # 隐藏光标
  print -n "\e[?25l"

  # 清屏并显示标题
  print -n "\e[2J\e[H"

  while true; do
    current_env="$(_llmc_get_current)"

    # 扫描当前目录
    local -a items=()
    local -a display_items=()

    builtin local item_type item_path item_display item_depth
    if (( tree_mode )); then
      while IFS='|' read -r item_type item_path item_display item_depth; do
        items+=("$item_type|$item_path|$item_display|$item_depth")

        # 构建显示文本
        local prefix_icon=""
        local suffix_mark=""
        local indent=""
        (( item_depth > 0 )) && indent="${(l:$(( item_depth * 2 )):: :)""}"

        if [[ "$item_type" == "dir" ]]; then
          prefix_icon="📁"
        else
          # 检查是否是当前环境
          if [[ -n "$current_env" && "$item_display" == "$current_env" ]]; then
            prefix_icon="💡"
          else
            prefix_icon="  "
          fi

          # 检查是否有星标
          if _llmc_is_starred "$item_display"; then
            suffix_mark=" 🌟"
          fi
        fi

        display_items+=("$indent$prefix_icon $item_display$suffix_mark")
      done < <(_llmc_scan_tree "$LLMC_ENV_DIR")
    else
      while IFS='|' read -r item_type item_path item_display; do
        items+=("$item_type|$item_path|$item_display")

        # 构建显示文本
        local prefix_icon=""
        local suffix_mark=""

        if [[ "$item_type" == "dir" ]]; then
          prefix_icon="📁"
        else
          # 检查是否是当前环境
          if [[ -n "$current_env" && "$item_display" == "$current_env" ]]; then
            prefix_icon="💡"
          else
            prefix_icon="  "
          fi

          # 检查是否有星标
          if _llmc_is_starred "$item_display"; then
            suffix_mark=" 🌟"
          fi
        fi

        display_items+=("$prefix_icon $item_display$suffix_mark")
      done < <(_llmc_scan_items "$current_dir" "$current_prefix")
    fi

    # 如果不在根目录，添加 ".." 返回项
    if (( ! tree_mode )) && [[ "$current_dir" != "$LLMC_ENV_DIR" ]]; then
      items=("dir|../..|.." "${items[@]}")
      display_items=("📂 .." "${display_items[@]}")
    fi

    # 检查是否有项目
    if (( ${#items} == 0 )); then
      print -r -- "当前目录为空：$current_dir"
      print -r -- "按 q 退出"
      local key="$(_llmc_read_key)"
      if [[ "$key" == "q" || "$key" == "esc" ]]; then
        break
      fi
      continue
    fi

    # 确保光标在有效范围内
    (( cursor < 1 )) && cursor=1
    (( cursor > ${#items} )) && cursor=${#items}

    # 展开视图启动时：尽量把当前环境定位到光标位置
    if (( tree_mode )) && [[ -n "$want_jump_env" ]]; then
      local -i idx
      for (( idx = 1; idx <= ${#items}; idx++ )); do
        local line="${items[idx]}"
        local t="${line%%|*}"
        local rest="${line#*|}"; rest="${rest#*|}"
        local disp="${rest%%|*}"
        if [[ "$t" == "env" && "$disp" == "$want_jump_env" ]]; then
          cursor=$idx
          break
        fi
      done
      want_jump_env=""
    fi

    # 清屏并重新绘制
    print -n "\e[2J\e[H"
    print -r -- "╔═══════════════════════════════════════════════════════════╗"
    print -r -- "║  LLMC - 环境选择器                                         ║"
    if (( tree_mode )); then
      print -r -- "║  当前: ${current_env:-<未选择>}                            ║"
    else
      print -r -- "║  当前: ${current_prefix:-/}                                ║"
    fi
    print -r -- "╠═══════════════════════════════════════════════════════════╣"
    if (( tree_mode )); then
      print -r -- "║  ↑/k:上  ↓/j:下  ←/h:上个目录  →/l:下个目录  Enter:选择  Space:星标  Tab:收起  q:退出 ║"
    else
      print -r -- "║  ↑/k:上  ↓/j:下  ←/h:返回  →/l/Enter:选择  Space:星标  Tab:展开  q:退出 ║"
    fi
    print -r -- "╚═══════════════════════════════════════════════════════════╝"
    print ""

    # 显示列表
    local -i i
    for (( i = 1; i <= ${#items}; i++ )); do
      if (( i == cursor )); then
        print -r -- "  ▶ ${display_items[i]}"
      else
        print -r -- "    ${display_items[i]}"
      fi
    done

    # 读取按键
    local key="$(_llmc_read_key)"

    case "$key" in
      k|up)
        (( cursor > 1 )) && (( cursor-- ))
        ;;
      j|down)
        (( cursor < ${#items} )) && (( cursor++ ))
        ;;
      h|left)
        if (( tree_mode )); then
          # 展开视图：跳到上一个目录
          local -i idx
          for (( idx = cursor - 1; idx >= 1; idx-- )); do
            local t="${items[idx]%%|*}"
            if [[ "$t" == "dir" ]]; then
              cursor=$idx
              break
            fi
          done
        elif [[ "$current_dir" != "$LLMC_ENV_DIR" ]]; then
          # 返回上级目录
          current_dir="${current_dir%/*}"
          [[ -z "$current_dir" ]] && current_dir="$LLMC_ENV_DIR"
          if [[ "$current_prefix" == */* ]]; then
            current_prefix="${current_prefix%/*}"
          else
            current_prefix=""
          fi
          if (( ${#cursor_stack} > 0 )); then
            cursor="${cursor_stack[-1]}"
            cursor_stack=("${cursor_stack[1,-2]}")
          else
            cursor=1
          fi
        fi
        ;;
      l|right)
        if (( tree_mode )); then
          # 展开视图：跳到下一个目录
          local -i idx
          for (( idx = cursor + 1; idx <= ${#items}; idx++ )); do
            local t="${items[idx]%%|*}"
            if [[ "$t" == "dir" ]]; then
              cursor=$idx
              break
            fi
          done
          continue
        fi
        _llmc_activate_current && return 0
        ;;
      $'\n')
        # Enter
        _llmc_activate_current && return 0
        ;;
      $'\t')
        if (( tree_mode )); then
          tree_mode=0
          current_dir="$saved_dir"
          current_prefix="$saved_prefix"
          cursor=$saved_cursor
          cursor_stack=("${saved_stack[@]}")
        else
          saved_dir="$current_dir"
          saved_prefix="$current_prefix"
          saved_cursor=$cursor
          saved_stack=("${cursor_stack[@]}")
          tree_mode=1
          want_jump_env="$current_env"
          cursor=1
        fi
        ;;
      ' ')
        # 切换星标
        local selected="${items[cursor]}"
        local sel_type="${selected%%|*}"
        local sel_display
        if (( tree_mode )); then
          sel_display="${selected#*|}"; sel_display="${sel_display#*|}"; sel_display="${sel_display%%|*}"
        else
          sel_display="${selected##*|}"
        fi

        if [[ "$sel_type" == "env" ]]; then
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

  _llmc_tui_restore
  trap - INT TERM EXIT
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
      local current_env="$(_llmc_get_current)"
      print -r -- "可用环境（星标优先）："

      # 先显示星标项
      if [[ -s "$LLMC_STARS_FILE" ]]; then
        while IFS= read -r name; do
          local marker="  "
          [[ -n "$current_env" && "$name" == "$current_env" ]] && marker="💡"
          print -r -- "  $marker 🌟 $name"
        done < "$LLMC_STARS_FILE"
      fi

      # 显示非星标项
      local item_type item_path item_display
      while IFS='|' read -r item_type item_path item_display; do
        [[ "$item_type" != "env" ]] && continue
        _llmc_is_starred "$item_display" && continue

        local marker="  "
        [[ -n "$current_env" && "$item_display" == "$current_env" ]] && marker="💡"
        print -r -- "  $marker    $item_display"
      done < <(_llmc_scan_items)
      ;;
    star)
      shift
      [[ -z "$1" ]] && { _llmc_err "用法：llmc star <name>"; return 2; }
      _llmc_add_star "$1"
      ;;
    unstar)
      shift
      [[ -z "$1" ]] && { _llmc_err "用法：llmc unstar <name>"; return 2; }
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
  ←/h        上一个目录（展开视图）；或返回上级目录（目录视图）
  →/l        下一个目录（展开视图）；或进入目录（目录视图）
  Enter      选择环境；在展开视图中 Enter 目录可进入目录视图
  Space      切换星标
  Tab        展开/收起目录树视图
  q/ESC      退出

HELP
      ;;
    *)
      # 尝试作为环境名直接切换（模糊匹配）
      local target="$cmd"
      local found=""

      # 查找匹配的环境
      local item_type item_path item_display
      while IFS='|' read -r item_type item_path item_display; do
        [[ "$item_type" != "env" ]] && continue
        if [[ "$item_display" == *"$target"* ]]; then
          found="$item_display"
          break
        fi
      done < <(_llmc_scan_items)

      if [[ -n "$found" ]]; then
        if command -v claude-switch >/dev/null 2>&1; then
          claude-switch use "$found"
        else
          _llmc_err "未找到 claude-switch 命令"
          return 1
        fi
      else
        _llmc_err "未找到匹配的环境：$target"
        _llmc_info "运行 'llmc list' 查看可用环境"
        return 1
      fi
      ;;
  esac
}

# Zsh 补全
_llmc_complete() {
  local -a subcmds
  subcmds=(
    'interactive:启动交互式选择器'
    'list:列出所有环境'
    'use:切换到指定环境（同 claude-switch use）'
    'show:显示默认记忆与当前变量（同 claude-switch show）'
    'open:打开环境目录（同 claude-switch open）'
    'new:新建环境（同 claude-switch new）'
    'edit:编辑环境（同 claude-switch edit）'
    'del:删除环境（同 claude-switch del）'
    'star:添加星标'
    'unstar:移除星标'
    'starred:列出星标项'
    'help:显示帮助'
  )

  if (( CURRENT == 2 )); then
    _describe 'llmc命令' subcmds

    # 添加环境名补全
    local -a envs
    local item_type item_path item_display
    while IFS='|' read -r item_type item_path item_display; do
      [[ "$item_type" == "env" ]] && envs+=("$item_display")
    done < <(_llmc_scan_items)
    (( ${#envs[@]} > 0 )) && _values '环境' "${envs[@]}"
  elif (( CURRENT == 3 )); then
    case "${words[2]}" in
      star|unstar|use|edit|del)
        local -a envs
        local item_type item_path item_display
        while IFS='|' read -r item_type item_path item_display; do
          [[ "$item_type" == "env" ]] && envs+=("$item_display")
        done < <(_llmc_scan_items)
        (( ${#envs[@]} > 0 )) && _values '环境' "${envs[@]}"
        ;;
    esac
  fi
}

# 设置补全
if (( $+functions[compdef] )); then
  compdef _llmc_complete llmc
fi

# 将 llmc 注册为 claude-switch 的子命令
if typeset -f claude-switch >/dev/null 2>&1; then
  # 保存原始函数
  functions[_claude_switch_orig]="${functions[claude-switch]}"

  # 重新定义 claude-switch
  claude-switch() {
    if [[ "$1" == "llmc" ]]; then
      shift
      llmc "$@"
    else
      _claude_switch_orig "$@"
    fi
  }
fi
