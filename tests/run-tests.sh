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
  tmp="$(mktemp -d)"
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
    echo "== claude-switch syncs VSCode settings env vars =="
    settings="$tmp/vscode-settings.json"
    cat >"$settings" <<'JSONC'
{
  // keep other keys
  "other": 1,
  "claudeCode.environmentVariables": [
    { "name": "ANTHROPIC_BASE_URL", "value": "old" },
    { "name": "ANTHROPIC_MODEL", "value": "oldmodel" },
    { "name": "FOO", "value": "bar" },
  ],
}
JSONC
    printf 'export ANTHROPIC_BASE_URL="https://x.example.com"\n' > "$CLAUDE_CODE_HOME/envs/foo.env"
    $sh -c "set -e; export CLAUDE_CODE_HOME='$tmp/.claude'; export CLAUDE_VSCODE_SETTINGS='$settings'; export CLAUDE_SYNC_VSCODE_SETTINGS=1; source '$BIN'; claude-switch use foo >/dev/null 2>&1"
    grep -q '"name": "ANTHROPIC_BASE_URL"' "$settings" || { echo "FAIL: VSCode settings missing ANTHROPIC_BASE_URL"; exit 1; }
    grep -q '"value": "https://x.example.com"' "$settings" || { echo "FAIL: VSCode settings did not update ANTHROPIC_BASE_URL value"; exit 1; }
    ! grep -q 'ANTHROPIC_MODEL' "$settings" || { echo "FAIL: VSCode settings should remove unset ANTHROPIC_MODEL"; exit 1; }
    grep -q '"name": "FOO"' "$settings" || { echo "FAIL: VSCode settings should preserve non-ANTHROPIC entries"; exit 1; }
  fi

  echo "== switch foo =="
  echo 'export ANTHROPIC_BASE_URL="https://x.example.com"' >> "$CLAUDE_CODE_HOME/envs/foo.env"
  _run 'claude-switch use foo ; test "$ANTHROPIC_BASE_URL" = "https://x.example.com"' || { echo "FAIL: switch foo"; exit 1; }

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
