# zsh-claude-tools

`claude-use` —— Claude Code API 环境管理小工具（Zsh）

- 列出全部环境 (`list`)
- 一键切换 (`claude-use <name>`)
- 新建/编辑/删除 (`new` / `edit` / `del`)
- 自动记忆上次选择，开机自动生效（若无记忆，按字典序取第一个；再无则不加载）
- 跨平台打开编辑器（`$VISUAL/$EDITOR`/VS Code/Sublime/nano/vim/open/xdg-open）
- 附带 Zsh Tab 补全

## 安装

```bash
git clone http://github.com/maemo/zsh-claude-tools
cd zsh-claude-tools
bash ./install.sh
source ~/.zshrc
