# zsh-claude-tools

`claude-use` —— Claude Code API 环境管理小工具（Zsh）

让你在不同 Claude Code API 环境配置之间快速切换，支持自动记忆、开机生效和 Zsh 补全。

---

## 功能特性

- **环境管理**
  - `list`：列出所有环境
  - `claude-use <name>`：切换环境
  - `new <name>`：新建配置并打开编辑器
  - `edit <name>`：编辑配置（不存在则创建模板）
  - `del <name>`：删除配置（需输入 `yes` 确认）
- **自动记忆**：记住上次使用的环境，下次开机自动生效  
- **补全支持**：Zsh Tab 补全子命令和配置名  
- **跨平台编辑器支持**：`$VISUAL` / `$EDITOR` / VS Code / Sublime / nano / vim / open / xdg-open  

---

## 安装

只需一条命令：

```sh
curl -fsSL https://raw.githubusercontent.com/iblueer/zsh-claude-tools/main/install.sh | sh
```

安装完成后，请执行：

```sh
source ~/.zshrc
claude-use list
```

确认工具可用。

---

## 卸载

执行：

```sh
curl -fsSL https://raw.githubusercontent.com/iblueer/zsh-claude-tools/main/uninstall.sh | sh
```

以上命令会删除 `~/.claude-tools` 并清理 `~/.zshrc` 中的配置。  
**注意**：不会删除你的 API 配置文件（默认在 `~/.claude/envs`）。  
如果要彻底清理：

```sh
rm -rf ~/.claude
```

---

## 使用示例

```sh
# 列出所有配置
claude-use list

# 新建一个配置（会生成 foo.env 并打开编辑器）
claude-use new foo

# 切换到 foo 环境
claude-use foo

# 编辑配置
claude-use edit foo

# 删除配置
claude-use del foo

# 显示默认记忆与当前生效的变量
claude-use show
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
bin/          主脚本 claude-use.zsh
completions/  Zsh 补全脚本
install.sh    安装脚本
uninstall.sh  卸载脚本
tests/        测试脚本
```

---

## 许可证

MIT License (见 [LICENSE](./LICENSE))
