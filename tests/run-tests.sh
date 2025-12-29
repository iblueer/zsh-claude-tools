#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")"/.. && pwd)"

for sh in zsh bash; do
  if [ "$sh" = bash ] && ! bash -c 'type mapfile >/dev/null 2>&1'; then
    echo "=== skipping bash (no mapfile builtin) ==="
    echo
    continue
  fi
  echo "=== testing $sh ==="
  mkdir -p "$ROOT/.tmp"
  tmp="$(mktemp -d "$ROOT/.tmp/claude-tools-test.XXXXXX")"
  trap 'rm -rf "$tmp"' EXIT
  export CLAUDE_CODE_HOME="$tmp/.claude"
  mkdir -p "$CLAUDE_CODE_HOME/envs"
  if [ "$sh" = zsh ]; then
    export ZDOTDIR="$tmp"
  fi
  BIN="$ROOT/bin/claude-switch.$([ "$sh" = zsh ] && echo zsh || echo bash)"

  _run() {
    $sh -c "set -e; source '$BIN'; $*"
  }

  echo "== list on empty =="
  out="$(_run 'claude-switch list')"
  echo "$out" | grep -q '（空）' || { echo "FAIL: list should be empty"; exit 1; }

  echo "== new foo =="
  _run 'claude-switch new foo' </dev/null || true
  test -f "$CLAUDE_CODE_HOME/envs/foo.env" || { echo "FAIL: foo.env not created"; exit 1; }

  echo "== edit bar (autocreate) =="
  rm -f "$CLAUDE_CODE_HOME/envs/bar.env"
  _run 'claude-switch edit bar' </dev/null || true
  test -f "$CLAUDE_CODE_HOME/envs/bar.env" || { echo "FAIL: bar.env not created"; exit 1; }

  echo "== llmc list preserves PATH =="
  LLMC="$ROOT/bin/llmc.$([ "$sh" = zsh ] && echo zsh || echo bash)"
  $sh -c "set -e; export CLAUDE_CODE_HOME='$tmp/.claude'; source '$LLMC'; before=\"\$PATH\"; llmc list >/dev/null; [ \"\$PATH\" = \"\$before\" ]" \
    || { echo "FAIL: llmc list modified PATH"; exit 1; }

  if [ "$sh" = zsh ]; then
    echo "== llmc interactive requires TTY =="
    out="$($sh -c "set -e; export CLAUDE_CODE_HOME='$tmp/.claude'; source '$LLMC'; llmc" 2>&1 || true)"
    echo "$out" | grep -q "需要 TTY" || { echo "FAIL: llmc should require TTY"; exit 1; }
  fi

  if command -v python3 >/dev/null 2>&1; then
    echo "== claude-switch syncs Claude settings.json =="
    settings="$CLAUDE_CODE_HOME/settings.json"
    cat >"$settings" <<'JSON'
{
  "model": "oldmodel",
  "other": 1,
  "env": {
    "FOO": "bar",
    "ANTHROPIC_BASE_URL": "old",
    "ANTHROPIC_AUTH_TOKEN": "oldtoken",
    "ANTHROPIC_MODEL": "oldmodel",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "oldmodel",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "oldhaiku",
    "ANTHROPIC_SMALL_FAST_MODEL": "oldsf"
  }
}
JSON
    cat >"$CLAUDE_CODE_HOME/envs/foo.env" <<'ENV'
export ANTHROPIC_BASE_URL="https://x.example.com"
export ANTHROPIC_MODEL="m1"
export ANTHROPIC_SMALL_FAST_MODEL="m2"
ENV
    $sh -c "set -e; export CLAUDE_CODE_HOME='$tmp/.claude'; export ANTHROPIC_BASE_URL='KEEP'; export ANTHROPIC_MODEL='KEEP'; export ANTHROPIC_SMALL_FAST_MODEL='KEEP'; source '$BIN'; claude-switch use foo >/dev/null 2>&1; test \"\$ANTHROPIC_BASE_URL\" = 'KEEP'; test \"\$ANTHROPIC_MODEL\" = 'KEEP'; test \"\$ANTHROPIC_SMALL_FAST_MODEL\" = 'KEEP'"
    grep -q '"model": "m1"' "$settings" || { echo "FAIL: claude settings should update top-level model"; exit 1; }
    grep -q '"ANTHROPIC_BASE_URL": "https://x.example.com"' "$settings" || { echo "FAIL: claude settings should update ANTHROPIC_BASE_URL"; exit 1; }
    grep -q '"ANTHROPIC_MODEL": "m1"' "$settings" || { echo "FAIL: claude settings should update ANTHROPIC_MODEL"; exit 1; }
    grep -q '"ANTHROPIC_SMALL_FAST_MODEL": "m2"' "$settings" || { echo "FAIL: claude settings should update ANTHROPIC_SMALL_FAST_MODEL"; exit 1; }
    grep -q '"ANTHROPIC_DEFAULT_SONNET_MODEL": "m1"' "$settings" || { echo "FAIL: claude settings should set DEFAULT_SONNET from ANTHROPIC_MODEL"; exit 1; }
    grep -q '"ANTHROPIC_DEFAULT_HAIKU_MODEL": "m2"' "$settings" || { echo "FAIL: claude settings should set DEFAULT_HAIKU from ANTHROPIC_SMALL_FAST_MODEL"; exit 1; }
    ! grep -q 'ANTHROPIC_AUTH_TOKEN' "$settings" || { echo "FAIL: claude settings should remove unset ANTHROPIC_AUTH_TOKEN"; exit 1; }
    grep -q '"FOO": "bar"' "$settings" || { echo "FAIL: claude settings should preserve non-ANTHROPIC env keys"; exit 1; }
  fi

  echo "== use does not mutate shell env =="
  echo 'export ANTHROPIC_BASE_URL="https://x.example.com"' >> "$CLAUDE_CODE_HOME/envs/foo.env"
  _run 'export ANTHROPIC_BASE_URL=KEEP ANTHROPIC_MODEL=KEEP ANTHROPIC_SMALL_FAST_MODEL=KEEP ANTHROPIC_DEFAULT_SONNET_MODEL=KEEP ANTHROPIC_DEFAULT_HAIKU_MODEL=KEEP; claude-switch use foo >/dev/null 2>&1; test "$ANTHROPIC_BASE_URL" = KEEP; test "$ANTHROPIC_MODEL" = KEEP; test "$ANTHROPIC_SMALL_FAST_MODEL" = KEEP; test "$ANTHROPIC_DEFAULT_SONNET_MODEL" = KEEP; test "$ANTHROPIC_DEFAULT_HAIKU_MODEL" = KEEP' || { echo "FAIL: use mutated shell env"; exit 1; }

  if command -v python3 >/dev/null 2>&1; then
    echo "== clear removes Claude settings env + model =="
    _run 'export ANTHROPIC_BASE_URL=KEEP ANTHROPIC_MODEL=KEEP ANTHROPIC_SMALL_FAST_MODEL=KEEP ANTHROPIC_DEFAULT_SONNET_MODEL=KEEP ANTHROPIC_DEFAULT_HAIKU_MODEL=KEEP; claude-switch clear >/dev/null 2>&1; test "$ANTHROPIC_BASE_URL" = KEEP; test "$ANTHROPIC_MODEL" = KEEP; test "$ANTHROPIC_SMALL_FAST_MODEL" = KEEP; test "$ANTHROPIC_DEFAULT_SONNET_MODEL" = KEEP; test "$ANTHROPIC_DEFAULT_HAIKU_MODEL" = KEEP' \
      || { echo "FAIL: clear should not touch shell env vars"; exit 1; }
    grep -q '"env": {}' "$CLAUDE_CODE_HOME/settings.json" || { echo "FAIL: clear should empty settings env"; exit 1; }
    ! grep -q '"model"' "$CLAUDE_CODE_HOME/settings.json" || { echo "FAIL: clear should remove settings model"; exit 1; }
  fi

  echo "== del reject =="
  ret=0
  ( echo "no" | _run 'claude-switch del foo' ) || ret=$?
  test $ret -eq 0 || { echo "FAIL: del reject should not fail"; exit 1; }
  test -f "$CLAUDE_CODE_HOME/envs/foo.env" || { echo "FAIL: foo.env should remain"; exit 1; }

  echo "== del yes =="
  ( echo "yes" | _run 'claude-switch del foo' )
  test ! -f "$CLAUDE_CODE_HOME/envs/foo.env" || { echo "FAIL: foo.env should be deleted"; exit 1; }

  rm -rf "$tmp"
  trap - EXIT
  echo
  done

echo "== all pass =="
