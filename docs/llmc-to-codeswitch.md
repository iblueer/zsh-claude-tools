# llmc → CodeSwitch.app 导入操作手册

本手册用于把 `llmc/claude-switch` 使用的环境文件（默认 `~/.claude/envs/**/*.env`）导入到 CodeSwitch.app 使用的配置文件：

- `~/.code-switch/claude-code.json`（你的机器上为：`/Users/maemolee/.code-switch/claude-code.json`）

## 导入规则（脚本做的事）

- 读取所有 `.env` 文件的：
  - `ANTHROPIC_BASE_URL` → `apiUrl`
  - `ANTHROPIC_AUTH_TOKEN` → `apiKey`
  - `ANTHROPIC_MODEL` / `ANTHROPIC_SMALL_FAST_MODEL` → `supportedModels`（自动推导）
- 以 `(apiUrl, apiKey)` 作为“去重”键：多个 env 指向同一套 endpoint+token，会合并成一个 provider，并合并 `supportedModels`
- 不会输出 `apiKey` 到终端

## 使用方式

1) 预览（不写文件）

```sh
python3 bin/code-switch-import-envs.py --dry-run
```

2) 增量导入（默认）：保留现有 providers，同时补充缺失 providers，并合并 `supportedModels`

```sh
python3 bin/code-switch-import-envs.py --mode incremental
```

3) 全量覆盖：用导入结果替换 `providers` 数组（同 `(apiUrl, apiKey)` 的记录会尽量保留原有 UI 字段，如 `name/icon/tint/accent`）

```sh
python3 bin/code-switch-import-envs.py --mode overwrite
```

4)（可选）写入前备份 json

```sh
python3 bin/code-switch-import-envs.py --backup
```

