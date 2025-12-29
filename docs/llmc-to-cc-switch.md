# llmc → cc-switch 迁移操作手册

本手册用于把 `llmc/claude-switch` 使用的环境文件（默认 `~/.claude/envs/**/*.env`）批量导入到 `cc-switch` 的数据库（默认 `~/.cc-switch/cc-switch.db`），方便后续在 `cc-switch` 里统一管理/切换。

## 会发生什么

- 不会删除或改动你的 `~/.claude/envs/**/*.env`
- 会写入 `~/.cc-switch/cc-switch.db`（SQLite）
- 每个 `.env` 文件会变成 `providers` 表里的一条 `app_type='claude'` 记录
- `.env` 中的变量会写入 `providers.settings_config` JSON 的 `env` 对象里
- 会基于 `.env` 里的字段补齐模型相关配置：
  - `ANTHROPIC_DEFAULT_SONNET_MODEL = ANTHROPIC_MODEL`
  - `ANTHROPIC_DEFAULT_OPUS_MODEL = ANTHROPIC_MODEL`
  - `ANTHROPIC_DEFAULT_HAIKU_MODEL = ANTHROPIC_SMALL_FAST_MODEL`
  - `settings_config.model = ANTHROPIC_MODEL`（若存在）

## 前置条件

- 已安装/初始化过 `cc-switch`，且存在 `~/.cc-switch/cc-switch.db`
- 本仓库代码已在本地（你正在使用的就是）
- 本机有 `python3`

## 迁移步骤

1) 备份数据库（你已备份可跳过）

```sh
cp -a ~/.cc-switch/cc-switch.db ~/.cc-switch/cc-switch.db.bak.$(date +%Y%m%d%H%M%S)
```

2) 预览将要导入的环境（不会写库）

```sh
python3 bin/cc-switch-import-envs.py --dry-run
```

输出格式为：`provider_id<TAB>显示名称<TAB>备注(通常是模型名)`

3) 执行导入（会写库）

```sh
python3 bin/cc-switch-import-envs.py
```

默认使用 `--mode incremental`：只插入缺失的 Provider，不覆盖你在 `cc-switch` 里已经改过的同名 Provider。

如果你希望用 `.env` 的内容全量覆盖同名 Provider（更新 `settings_config.env` / `model` 等），请使用：

```sh
python3 bin/cc-switch-import-envs.py --mode overwrite
```

4)（可选）用 sqlite3 验证导入结果

```sh
sqlite3 ~/.cc-switch/cc-switch.db "select id, name from providers where app_type='claude' order by name;"
```

5) 在 cc-switch 里选择导入后的环境

- 如果 cc-switch UI 支持切换 Provider：直接在 UI 中找到对应 `name`（例如 `qiniu/minimax/minimax-m2.1`）并选中即可
- 或者手动修改 `~/.cc-switch/settings.json`：
  - 把 `currentProviderClaude` 设置为目标 `provider_id`
  - 例如：`env_qiniu__minimax__minimax-m2.1`

## ID 命名规则（用于定位 currentProviderClaude）

脚本生成的 `provider_id` 为稳定值：

- 前缀：`env_`
- 再把 env 相对路径（去掉 `.env`）里的 `/` 替换为 `__`

示例：

- `~/.claude/envs/default.env` → `env_default`
- `~/.claude/envs/moonshot/kimi-k2-turbo-preview.env` → `env_moonshot__kimi-k2-turbo-preview`
- `~/.claude/envs/routers/temp/1000.env` → `env_routers__temp__1000`

## 重复执行与更新

可以重复运行导入脚本：同一个 env 文件会覆盖更新同名 `provider_id` 的记录（upsert），便于你修改 `.env` 后再次同步到 `cc-switch`。

## 回滚

如果导入后出现问题，直接用备份恢复：

```sh
cp -a ~/.cc-switch/cc-switch.db.bak.YYYYMMDDhhmmss ~/.cc-switch/cc-switch.db
```

（也可以使用你自己已有的备份文件恢复。）
