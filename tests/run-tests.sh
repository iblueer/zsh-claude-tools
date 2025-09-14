#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")"/.. && pwd)"

for sh in zsh bash; do
  echo "=== testing $sh ==="
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  export CLAUDE_CODE_HOME="$tmp/.claude"
  mkdir -p "$CLAUDE_CODE_HOME/envs"
  if [ "$sh" = zsh ]; then
    export ZDOTDIR="$tmp"
  fi
  BIN="$ROOT/bin/claude-use.$([ "$sh" = zsh ] && echo zsh || echo bash)"

  _run() {
    $sh -c "set -e; source '$BIN'; $*"
  }

  echo "== list on empty =="
  out="$(_run 'claude-use list')"
  echo "$out" | grep -q '（空）' || { echo "FAIL: list should be empty"; exit 1; }

  echo "== new foo =="
  _run 'claude-use new foo' </dev/null || true
  test -f "$CLAUDE_CODE_HOME/envs/foo.env" || { echo "FAIL: foo.env not created"; exit 1; }

  echo "== edit bar (autocreate) =="
  rm -f "$CLAUDE_CODE_HOME/envs/bar.env"
  _run 'claude-use edit bar' </dev/null || true
  test -f "$CLAUDE_CODE_HOME/envs/bar.env" || { echo "FAIL: bar.env not created"; exit 1; }

  echo "== switch foo =="
  echo 'export ANTHROPIC_BASE_URL="https://x.example.com"' >> "$CLAUDE_CODE_HOME/envs/foo.env"
  _run 'claude-use foo ; test "$ANTHROPIC_BASE_URL" = "https://x.example.com"' || { echo "FAIL: switch foo"; exit 1; }

  echo "== del reject =="
  ret=0
  ( echo "no" | _run 'claude-use del foo' ) || ret=$?
  test $ret -eq 0 || { echo "FAIL: del reject should not fail"; exit 1; }
  test -f "$CLAUDE_CODE_HOME/envs/foo.env" || { echo "FAIL: foo.env should remain"; exit 1; }

  echo "== del yes =="
  ( echo "yes" | _run 'claude-use del foo' )
  test ! -f "$CLAUDE_CODE_HOME/envs/foo.env" || { echo "FAIL: foo.env should be deleted"; exit 1; }

  rm -rf "$tmp"
  trap - EXIT
  echo
  done

echo "== all pass =="
