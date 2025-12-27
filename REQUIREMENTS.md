# zsh-claude-tools 开发需求文档

## 项目概述

zsh-claude-tools 是一个 Claude Code API 环境管理工具，支持在 Zsh 和 Bash 中快速切换不同的 API 配置环境。

---

## 核心需求

### 1. 新增交互式选择器 `llmc` 命令

#### 功能描述
提供一个类似 vim 风格的交互式 TUI 界面，用于浏览和选择环境配置。

#### 具体要求

**1.1 基础功能**
- 创建独立的 `llmc.zsh` 和 `llmc.bash` 脚本
- 支持目录结构浏览（支持 `~/.claude/envs` 下的子目录）
- 支持 `.env` 文件的选择和切换
- 实时显示当前生效的环境（标记为 💡）

**1.2 交互式操作**
- `↑/k` - 向上移动光标
- `↓/j` - 向下移动光标
- `←/h` - 返回父目录
- `→/l/Enter` - 进入子目录或选择环境文件
- `Space/Tab` - 切换当前项的星标状态
- `q/ESC` - 退出选择器

**1.3 星标系统**
- 支持标记常用环境为星标 🌟
- 星标数据保存在 `~/.claude/stars` 文件
- 在列表中优先显示星标项
- 提供命令行接口：
  - `llmc star <name>` - 添加星标
  - `llmc unstar <name>` - 移除星标
  - `llmc starred` - 列出所有星标项

**1.4 命令行模式**
- `llmc` - 启动交互式选择器
- `llmc list` - 列出所有环境（星标优先）
- `llmc <name>` - 直接切换到指定环境（支持模糊匹配）
- `llmc help` - 显示帮助信息

**1.5 集成要求**
- `claude-switch llmc` 应该能够调用 llmc 交互式选择器
- llmc 选择环境后，应调用 `claude-switch use <name>` 完成切换
- 环境名传递给 `claude-switch use` 时，必须去除 `.env` 后缀

---

### 2. 修复命令提示信息

#### 问题描述
历史兼容命令 `claude-use` 已移除；所有提示与文档统一使用 `claude-switch`。

#### 修复位置
- `bin/claude-switch.zsh`
  - `_cu_cmd_switch` 函数的用法提示
  - `_cu_cmd_new` 函数的用法提示
  - `_cu_cmd_edit` 函数的用法提示
  - `_cu_cmd_del` 函数的用法提示

- `bin/claude-switch.bash`
  - 同上对应函数的用法提示

#### 预期结果
所有错误提示应显示：
- `用法：claude-switch use <name>`
- `用法：claude-switch new <name>`
- `用法：claude-switch edit <name>`
- `用法：claude-switch del <name>`

---

### 3. 静默自动加载环境

#### 问题描述
每次 `source ~/.zshrc` 或 `source ~/.bashrc` 时，`_cu_autoload_on_startup` 函数会显示加载信息、spinner 和环境变量详情，造成干扰。

#### 解决方案
修改 `_cu_autoload_on_startup` 函数，使其：
- 直接调用 `_cu_load_env` 而不是 `_cu_cmd_switch`
- 将所有输出重定向到 `/dev/null`
- 仅在环境变量加载失败时静默失败，不中断 shell 初始化

#### 预期效果
- `source ~/.zshrc` 后无任何输出
- 环境变量已在后台正确加载
- 仅在用户主动使用 `claude-switch use` 时才显示完整输出

---

### 4. 安装脚本改进

#### 4.1 环境变量统一
- 所有脚本统一使用 `CLAUDE_CODE_HOME` 环境变量
- 默认值：`$HOME/.claude`
- 移除任何 `CLAUDE_HOME` 的使用

#### 4.2 llmc 模块加载
在生成的 init 脚本中添加 llmc 的加载：

**bash 版本** (`init.bash`):
```bash
: ${CLAUDE_CODE_HOME:="$HOME/.claude"}
if [ -f "$HOME/.claude-tools/bin/claude-switch.bash" ]; then
  . "$HOME/.claude-tools/bin/claude-switch.bash"
fi
if [ -f "$HOME/.claude-tools/bin/llmc.bash" ]; then
  . "$HOME/.claude-tools/bin/llmc.bash"
fi
```

**zsh 版本** (`init.zsh`):
```zsh
: ${CLAUDE_CODE_HOME:="$HOME/.claude"}

case "$-" in
  *i*)
    if [ -f "$HOME/.claude-tools/bin/claude-switch.zsh" ]; then
      . "$HOME/.claude-tools/bin/claude-switch.zsh"
    fi
    if [ -f "$HOME/.claude-tools/bin/llmc.zsh" ]; then
      . "$HOME/.claude-tools/bin/llmc.zsh"
    fi
    ;;
esac
```

#### 4.3 文件复制
`install.sh` 和 `install_locally.sh` 都需要下载/复制：
- `bin/llmc.zsh`
- `bin/llmc.bash`

---

### 5. README 更新

需要在 README.md 中添加：

#### 5.1 功能特性更新
- 在环境管理部分突出 `llmc` 作为主要命令
- 添加"星标功能"说明
- 添加"交互式导航"说明

#### 5.2 新增 llmc 使用示例章节
包含：
- 交互式选择器的启动方式
- 快捷键说明
- 命令行模式的使用示例
- 星标管理示例

#### 5.3 项目结构更新
在项目结构中添加 `llmc.zsh/llmc.bash` 的说明

---

## 技术细节

### 数组索引问题（仅 Zsh）
- Zsh 数组索引从 1 开始
- 在 `llmc.zsh` 中处理数组时必须使用正确的索引
- 注意 `${items[i]}` vs `${items[i+1]}` 的使用场景

### 路径处理
- 调用 `claude-switch use` 时，环境名必须：
  1. 移除 `$CLAUDE_USE_ENV_DIR/` 前缀
  2. 移除 `.env` 后缀
  3. 保留中间的相对路径（如 `qiniu/deepseek/deepseek-v3.2`）

示例：
```bash
# 错误
claude-switch use "/Users/user/.claude/envs/qiniu/deepseek.env"

# 正确
claude-switch use "qiniu/deepseek"
```

### 兼容性要求
- 支持 Zsh 5.0+
- 支持 Bash 4.0+
- 支持 macOS、Linux、Windows Git Bash
- 按键读取需要处理不同平台的差异

---

## 非功能性需求

### 代码质量
- 所有函数必须有适当的错误处理
- 避免不必要的输出污染用户终端
- 保持与现有代码风格一致

### 性能
- 交互式选择器响应时间 < 100ms
- 环境切换时间 < 500ms
- 支持大量环境文件（> 100 个）不卡顿

### 用户体验
- 提供清晰的错误信息
- 操作响应及时
- 快捷键符合 vim 用户习惯
- 星标项优先显示，方便快速访问

---

## 实现优先级

### P0（必须实现）
1. llmc 交互式选择器基础功能
2. 修复命令提示信息
3. 静默自动加载环境
4. 安装脚本的环境变量统一

### P1（重要）
1. 星标系统
2. 目录导航支持
3. llmc 模块的安装和加载
4. README 更新

### P2（可选）
1. 模糊搜索功能
2. 颜色高亮
3. 性能优化

---

## 测试要点

### 功能测试
- [ ] llmc 交互式选择器能正常启动
- [ ] 上下左右键导航正常工作
- [ ] 星标切换功能正常
- [ ] 环境切换后变量正确加载
- [ ] 错误提示信息正确显示
- [ ] source ~/.zshrc 无输出

### 兼容性测试
- [ ] Zsh 环境下所有功能正常
- [ ] Bash 环境下所有功能正常
- [ ] macOS 系统测试通过
- [ ] Linux 系统测试通过

### 边界测试
- [ ] 空环境目录
- [ ] 超长文件名
- [ ] 多层嵌套目录
- [ ] 特殊字符处理

---

## 文档要求

需要更新的文档：
- [x] REQUIREMENTS.md（本文档）
- [ ] README.md（添加 llmc 使用说明）
- [ ] 可选：CHANGELOG.md（记录版本变更）

---

## 版本规划

建议版本号：`v2.0.0`

理由：新增 llmc 交互式选择器是重大功能更新，符合语义化版本控制的主版本号升级条件。
