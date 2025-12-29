#!/usr/bin/env python3
import argparse
import copy
import json
import os
import re
import sqlite3
import sys
import time


def now_ms() -> str:
    return str(int(time.time() * 1000))


def iter_env_files(env_root: str):
    for dirpath, dirnames, filenames in os.walk(env_root):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for filename in filenames:
            if filename.startswith("."):
                continue
            if not filename.endswith(".env"):
                continue
            yield os.path.join(dirpath, filename)


def strip_inline_comment(value: str) -> str:
    in_single = False
    in_double = False
    for i, ch in enumerate(value):
        if ch == "'" and not in_double:
            in_single = not in_single
        elif ch == '"' and not in_single:
            in_double = not in_double
        elif ch == "#" and not in_single and not in_double:
            return value[:i].rstrip()
    return value.rstrip()


def unquote(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        value = value[1:-1]
    return value


_KEY_RE = re.compile(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$")


def parse_env_file(path: str) -> dict[str, str]:
    env: dict[str, str] = {}
    with open(path, "r", encoding="utf-8") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            match = _KEY_RE.match(raw_line)
            if not match:
                continue
            key, rest = match.group(1), match.group(2)
            value = unquote(strip_inline_comment(rest))
            if value == "":
                continue
            env[key] = value
    return env


def provider_id(prefix: str, relative_name: str) -> str:
    # Keep it stable and filesystem/UI friendly.
    base = relative_name.replace("/", "__")
    base = re.sub(r"[^A-Za-z0-9_.-]+", "_", base)
    return f"{prefix}{base}"


def load_default_claude_template(conn: sqlite3.Connection) -> dict:
    row = conn.execute(
        "select settings_config from providers where id='default' and app_type='claude'"
    ).fetchone()
    if not row or not row[0]:
        return {"env": {}}
    try:
        template = json.loads(row[0])
        if not isinstance(template, dict):
            return {"env": {}}
        if "env" not in template or not isinstance(template.get("env"), dict):
            template["env"] = {}
        return template
    except json.JSONDecodeError:
        return {"env": {}}


def upsert_provider(
    conn: sqlite3.Connection,
    *,
    id_: str,
    name: str,
    settings_config: dict,
    notes: str | None,
    mode: str,
):
    encoded = json.dumps(settings_config, ensure_ascii=False, separators=(",", ":"))
    existing = conn.execute(
        "select created_at from providers where id=? and app_type='claude'", (id_,)
    ).fetchone()

    if existing:
        if mode == "incremental":
            return "skipped"
        conn.execute(
            """
            update providers
               set name=?,
                   settings_config=?,
                   category='custom',
                   notes=?
             where id=? and app_type='claude'
            """,
            (name, encoded, notes or "", id_),
        )
        return "updated"

    conn.execute(
        """
        insert into providers (
          id, app_type, name, settings_config,
          website_url, category, created_at, sort_index, notes,
          icon, icon_color, meta, is_current
        ) values (
          ?, 'claude', ?, ?,
          '', 'custom', ?, null, ?,
          '', '', '{}', 0
        )
        """,
        (id_, name, encoded, now_ms(), notes or ""),
    )
    return "inserted"


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Import ~/.claude/envs/*.env into cc-switch providers (app_type=claude)."
    )
    parser.add_argument(
        "--env-root",
        default=os.path.expanduser("~/.claude/envs"),
        help="Root directory containing .env files (default: ~/.claude/envs).",
    )
    parser.add_argument(
        "--db",
        default=os.path.expanduser("~/.cc-switch/cc-switch.db"),
        help="Path to cc-switch SQLite db (default: ~/.cc-switch/cc-switch.db).",
    )
    parser.add_argument(
        "--id-prefix",
        default="env_",
        help="Prefix for provider ids to keep them stable (default: env_).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print planned changes without writing to the database.",
    )
    parser.add_argument(
        "--mode",
        choices=["incremental", "overwrite"],
        default="incremental",
        help="Import mode: incremental=only insert missing providers; overwrite=update existing providers (default: incremental).",
    )
    args = parser.parse_args(argv)

    env_root = os.path.abspath(args.env_root)
    if not os.path.isdir(env_root):
        print(f"env root not found: {env_root}", file=sys.stderr)
        return 2

    env_files = sorted(iter_env_files(env_root))
    if not env_files:
        print(f"no .env files found under: {env_root}", file=sys.stderr)
        return 2

    conn = sqlite3.connect(args.db)
    conn.row_factory = sqlite3.Row

    try:
        template = load_default_claude_template(conn)
        planned: list[tuple[str, str, str]] = []
        counts = {"inserted": 0, "updated": 0, "skipped": 0}

        for path in env_files:
            rel = os.path.relpath(path, env_root)
            rel_no_ext = rel[:-4] if rel.endswith(".env") else rel
            rel_no_ext = rel_no_ext.replace(os.sep, "/")

            raw_env = parse_env_file(path)

            anthropic_model = raw_env.get("ANTHROPIC_MODEL")
            small_fast_model = raw_env.get("ANTHROPIC_SMALL_FAST_MODEL")

            env = dict(raw_env)
            if anthropic_model:
                env["ANTHROPIC_DEFAULT_SONNET_MODEL"] = anthropic_model
                env["ANTHROPIC_DEFAULT_OPUS_MODEL"] = anthropic_model
            else:
                env.pop("ANTHROPIC_DEFAULT_SONNET_MODEL", None)
                env.pop("ANTHROPIC_DEFAULT_OPUS_MODEL", None)

            if small_fast_model:
                env["ANTHROPIC_DEFAULT_HAIKU_MODEL"] = small_fast_model
            else:
                env.pop("ANTHROPIC_DEFAULT_HAIKU_MODEL", None)

            cfg = copy.deepcopy(template)
            cfg["env"] = env
            if anthropic_model:
                cfg["model"] = anthropic_model
            else:
                cfg.pop("model", None)

            id_ = provider_id(args.id_prefix, rel_no_ext)
            name = rel_no_ext
            notes = anthropic_model or ""
            planned.append((id_, name, notes))

            if not args.dry_run:
                result = upsert_provider(
                    conn,
                    id_=id_,
                    name=name,
                    settings_config=cfg,
                    notes=notes,
                    mode=args.mode,
                )
                counts[result] += 1

        if args.dry_run:
            for id_, name, notes in planned:
                print(f"{id_}\t{name}\t{notes}")
            return 0

        conn.commit()
        print(
            f"imported {len(env_files)} env(s) into {args.db} "
            f"(inserted={counts['inserted']}, updated={counts['updated']}, skipped={counts['skipped']}, mode={args.mode})"
        )
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
