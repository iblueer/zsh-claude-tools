#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import re
import shutil
import sys
import time
from urllib.parse import urlparse


def now_ms() -> int:
    return int(time.time() * 1000)


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


def atomic_write_json(path: str, data) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp_path = f"{path}.tmp"
    with open(tmp_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.replace(tmp_path, path)


def load_json(path: str) -> dict:
    if not os.path.exists(path):
        return {"providers": []}
    with open(path, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            raise ValueError(f"invalid json: {path}: {e}") from e
    if not isinstance(data, dict):
        raise ValueError(f"invalid json root type (expect object): {path}")
    if "providers" not in data or not isinstance(data["providers"], list):
        data["providers"] = []
    return data


def url_host(url: str) -> str:
    try:
        parsed = urlparse(url)
        if parsed.netloc:
            return parsed.netloc
    except Exception:
        pass
    return url


def key_fingerprint(api_key: str) -> str:
    return hashlib.sha256(api_key.encode("utf-8")).hexdigest()[:6]


def model_patterns(env: dict[str, str]) -> dict[str, bool]:
    patterns: dict[str, bool] = {}
    for key in ("ANTHROPIC_MODEL", "ANTHROPIC_SMALL_FAST_MODEL"):
        value = (env.get(key) or "").strip()
        if not value:
            continue
        if "/" in value:
            prefix = value.split("/", 1)[0].strip()
            if prefix:
                patterns[f"{prefix}/*"] = True
        else:
            patterns[value] = True
    return patterns


def normalize_supported_models(obj) -> dict[str, bool]:
    if not isinstance(obj, dict):
        return {}
    out: dict[str, bool] = {}
    for k, v in obj.items():
        if isinstance(k, str) and bool(v):
            out[k] = True
    return out


def provider_key(provider: dict) -> tuple[str, str] | None:
    api_url = provider.get("apiUrl")
    api_key = provider.get("apiKey")
    if not isinstance(api_url, str) or not api_url.strip():
        return None
    if not isinstance(api_key, str) or not api_key.strip():
        return None
    return (api_url.strip(), api_key.strip())


def dedupe_existing_providers(providers: list[dict]) -> tuple[list[dict], int]:
    seen: dict[tuple[str, str], dict] = {}
    out: list[dict] = []
    removed = 0
    for p in providers:
        if not isinstance(p, dict):
            removed += 1
            continue
        key = provider_key(p)
        if not key:
            out.append(p)
            continue
        if key in seen:
            existing = seen[key]
            merged = normalize_supported_models(existing.get("supportedModels"))
            merged.update(normalize_supported_models(p.get("supportedModels")))
            existing["supportedModels"] = merged
            removed += 1
            continue
        p["supportedModels"] = normalize_supported_models(p.get("supportedModels"))
        seen[key] = p
        out.append(p)
    return out, removed


def default_provider_record(
    *,
    id_value: int,
    name: str,
    api_url: str,
    api_key: str,
    supported_models: dict[str, bool],
) -> dict:
    return {
        "id": id_value,
        "name": name,
        "apiUrl": api_url,
        "apiKey": api_key,
        "officialSite": "",
        "icon": "adobe",
        "tint": "rgba(15, 23, 42, 0.12)",
        "accent": "#0a84ff",
        "enabled": True,
        "supportedModels": supported_models,
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Import llmc envs (~/.claude/envs/*.env) into CodeSwitch.app claude-code.json."
    )
    parser.add_argument(
        "--env-root",
        default=os.path.expanduser("~/.claude/envs"),
        help="Root directory containing .env files (default: ~/.claude/envs).",
    )
    parser.add_argument(
        "--out",
        default=os.path.expanduser("~/.code-switch/claude-code.json"),
        help="Output CodeSwitch provider json (default: ~/.code-switch/claude-code.json).",
    )
    parser.add_argument(
        "--mode",
        choices=["incremental", "overwrite"],
        default="incremental",
        help="incremental=merge into existing; overwrite=replace providers with imported ones (default: incremental).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print summary without writing (never prints apiKey).",
    )
    parser.add_argument(
        "--backup",
        action="store_true",
        help="Create a .bak copy of the output json before writing.",
    )
    args = parser.parse_args(argv)

    env_root = os.path.abspath(args.env_root)
    out_path = os.path.abspath(os.path.expanduser(args.out))

    if not os.path.isdir(env_root):
        print(f"env root not found: {env_root}", file=sys.stderr)
        return 2

    env_files = sorted(iter_env_files(env_root))
    if not env_files:
        print(f"no .env files found under: {env_root}", file=sys.stderr)
        return 2

    # Group by (apiUrl, apiKey), union supportedModels across env files.
    groups: dict[tuple[str, str], dict] = {}
    skipped_envs = 0
    for path in env_files:
        rel = os.path.relpath(path, env_root)
        rel_no_ext = rel[:-4] if rel.endswith(".env") else rel
        rel_no_ext = rel_no_ext.replace(os.sep, "/")

        env = parse_env_file(path)
        api_url = (env.get("ANTHROPIC_BASE_URL") or "").strip()
        api_key = (env.get("ANTHROPIC_AUTH_TOKEN") or "").strip()
        if not api_url or not api_key:
            skipped_envs += 1
            continue

        key = (api_url, api_key)
        entry = groups.get(key)
        if not entry:
            entry = {
                "apiUrl": api_url,
                "apiKey": api_key,
                "env_names": [rel_no_ext],
                "supportedModels": {},
            }
            groups[key] = entry
        else:
            entry["env_names"].append(rel_no_ext)

        entry["supportedModels"].update(model_patterns(env))

    desired = list(groups.values())
    desired.sort(key=lambda x: (url_host(x["apiUrl"]), x["env_names"][0]))

    data = load_json(out_path)
    providers = data.get("providers") if isinstance(data.get("providers"), list) else []
    providers, removed_dupes = dedupe_existing_providers(providers)

    existing_by_key: dict[tuple[str, str], dict] = {}
    for p in providers:
        if not isinstance(p, dict):
            continue
        key = provider_key(p)
        if key:
            existing_by_key[key] = p

    next_id = max(
        [p.get("id", 0) for p in providers if isinstance(p, dict) and isinstance(p.get("id"), int)]
        + [now_ms()]
    )

    def allocate_id() -> int:
        nonlocal next_id
        next_id += 1
        return next_id

    imported_providers: list[dict] = []
    inserted = updated = skipped = 0

    for d in desired:
        key = (d["apiUrl"], d["apiKey"])
        supported_models = normalize_supported_models(d.get("supportedModels"))
        existing = existing_by_key.get(key)

        if existing:
            if args.mode == "incremental":
                merged = normalize_supported_models(existing.get("supportedModels"))
                merged.update(supported_models)
                existing["supportedModels"] = merged
                updated += 1
                imported_providers.append(existing)
            else:
                # overwrite mode: keep some existing UI fields, but replace supportedModels.
                keep = dict(existing)
                keep["supportedModels"] = supported_models
                imported_providers.append(keep)
                updated += 1
            continue

        # New provider record.
        host = url_host(d["apiUrl"])
        name = host
        if d.get("env_names"):
            first = d["env_names"][0].split("/", 1)[0]
            if first and first != "default":
                name = f"{first}@{host}#{key_fingerprint(d['apiKey'])}"

        imported_providers.append(
            default_provider_record(
                id_value=allocate_id(),
                name=name,
                api_url=d["apiUrl"],
                api_key=d["apiKey"],
                supported_models=supported_models,
            )
        )
        inserted += 1

    if args.mode == "incremental":
        # Keep existing providers (including those without apiUrl/apiKey), then ensure imported ones are present/merged.
        # Preserve order: existing first, then new providers appended.
        kept: list[dict] = []
        kept_keys: set[tuple[str, str]] = set()
        for p in providers:
            if not isinstance(p, dict):
                continue
            key = provider_key(p)
            if key:
                kept_keys.add(key)
            kept.append(p)
        for p in imported_providers:
            key = provider_key(p)
            if key and key in kept_keys:
                continue
            kept.append(p)
        data["providers"] = kept
    else:
        data["providers"] = imported_providers

    if args.dry_run:
        print(
            f"env_files={len(env_files)} skipped_envs={skipped_envs} "
            f"desired_providers={len(desired)} existing_providers={len(providers)} removed_dupes={removed_dupes} "
            f"mode={args.mode} inserted={inserted} updated={updated}"
        )
        for p in data["providers"]:
            if not isinstance(p, dict):
                continue
            key = provider_key(p)
            if not key:
                continue
            api_url, _ = key
            name = p.get("name", "")
            sm = normalize_supported_models(p.get("supportedModels"))
            print(f"- {name}\t{api_url}\tmodels={len(sm)}")
        return 0

    if args.backup and os.path.exists(out_path):
        shutil.copy2(out_path, f"{out_path}.bak")

    atomic_write_json(out_path, data)
    # Do not print apiKey.
    print(
        f"updated {out_path} (mode={args.mode}, inserted={inserted}, updated={updated}, "
        f"removed_dupes={removed_dupes}, skipped_envs={skipped_envs})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
