# zsh-claude-tools

`claude-use` —— Claude Code API 环境管理小工具（Zsh）
> `claude-use` 可以让你在不同的 Claude Code API 配置之间快速切换，支持记忆功能和自动加载。  

- 列出全部环境 (`list`)
- 一键切换 (`claude-use <name>`)
- 新建/编辑/删除 (`new` / `edit` / `del`)
- 自动记忆上次选择，开机自动生效（若无记忆，按字典序取第一个；再无则不加载）
- 跨平台打开编辑器（`$VISUAL/$EDITOR`/VS Code/Sublime/nano/vim/open/xdg-open）
- 附带 Zsh Tab 补全

## 安装
在线安装：
```sh
curl -fsSL https://raw.githubusercontent.com/maemo/zsh-claude-tools/main/install.sh | sh
```

安装完成后，请执行以下指令以验证安装成功：
```sh
source ~/.zshrc
claude-use list
```

## 卸载
在线卸载：
```sh
curl -fsSL https://raw.githubusercontent.com/maemo/zsh-claude-tools/main/uninstall.sh | sh
```
以上命令会删除 `~/.claude-tools` 并清理 `~/.zshrc` 中的配置，但不会删除你的 API 配置文件（位于 `~/.claude/envs`）。  