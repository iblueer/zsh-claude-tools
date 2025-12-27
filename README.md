# zsh-claude-tools

`claude-switch` 和 `llmc` —— Claude Code API 环境管理工具（Zsh/Bash）

让你在不同 Claude Code API 环境配置之间快速切换，支持自动记忆、开机生效、交互式选择器，兼容 Zsh、Bash（含 Windows Git Bash）。

---

## 功能特性

- **交互式选择器 (llmc)**
  - vim 风格的 TUI 界面，快速浏览和选择环境
  - 支持目录结构浏览和导航
  - 星标系统 🌟 标记常用环境
  - 实时显示当前生效环境 💡
  - 支持快捷键：↑/k/↓/j 移动，←/h 返回，→/l/Enter 选择
- **环境管理**
  - `llmc`：启动交互式选择器（推荐）
  - `list`：列出所有环境
  - `claude-switch use <name>`：切换环境
  - `claude-switch <name>`：切换环境（兼容旧用法）
  - `new <name>`：新建配置并打开编辑器
  - `edit <name>`：编辑配置（不存在则创建模板）
  - `del <name>`：删除配置（需输入 `yes` 确认）
- **自动记忆**：记住上次使用的环境，下次开机自动生效
- **补全支持**：Zsh Tab 补全子命令和配置名（Bash 暂无补全）
- **跨平台编辑器支持**：`$VISUAL` / `$EDITOR` / VS Code / Sublime / nano / vim / open / xdg-open  

---

## 安装

只需一条命令：

```sh
curl -fsSL https://raw.githubusercontent.com/iblueer/zsh-claude-tools/main/install.sh | sh
```

安装完成后，请执行：

```sh
source ~/.zshrc   # 若使用 Zsh
# 或
source ~/.bashrc  # 若使用 Bash
llmc              # 启动交互式选择器
```

确认工具可用。

---

## 卸载

执行：

```sh
curl -fsSL https://raw.githubusercontent.com/iblueer/zsh-claude-tools/main/uninstall.sh | sh
```

以上命令会删除 `~/.claude-tools` 并清理 `~/.zshrc` 或 `~/.bashrc` 中的配置。  
**注意**：不会删除你的 API 配置文件（默认在 `~/.claude/envs`）。  
如果要彻底清理：

```sh
rm -rf ~/.claude
```

---

## 使用示例

### 交互式选择器 (推荐)

```sh
# 启动交互式选择器
llmc

# 交互式快捷键：
#   ↑/k        向上移动
#   ↓/j        向下移动
#   ←/h        返回上级目录
#   →/l/Enter  进入目录或选择环境
#   Space/Tab  切换星标
#   q/ESC      退出

# 列出所有环境（星标优先）
llmc list

# 星标管理
llmc star myenv       # 添加星标
llmc unstar myenv     # 移除星标
llmc starred          # 列出所有星标项

# 直接切换（支持模糊匹配）
llmc prod             # 切换到包含 "prod" 的环境
```

### 命令行模式

```sh
# 列出所有配置
claude-switch list

# 新建一个配置（会生成 foo.env 并打开编辑器）
claude-switch new foo

# 切换到 foo 环境
claude-switch use foo
# 或使用兼容语法
claude-switch foo

# 编辑配置
claude-switch edit foo

# 删除配置
claude-switch del foo

# 显示默认记忆与当前生效的变量
claude-switch show

# 打开环境目录
claude-switch open

# 也可以通过 claude-switch 调用 llmc
claude-switch llmc
```

环境文件默认保存在：  
```
~/.claude/envs/*.env
```

内容示例：

```sh
export ANTHROPIC_BASE_URL="https://anyrouter.top"
export ANTHROPIC_AUTH_TOKEN="your-token"
export ANTHROPIC_MODEL="claude-3-7-sonnet"
export ANTHROPIC_SMALL_FAST_MODEL="claude-3-haiku"
```

---

## 项目结构

```
bin/          主脚本 claude-switch.zsh/claude-switch.bash
             交互式选择器 llmc.zsh/llmc.bash
completions/  Zsh 补全脚本
install.sh    安装脚本
uninstall.sh  卸载脚本
tests/        测试脚本
```

---

## 许可证

MIT License (见 [LICENSE](./LICENSE))
