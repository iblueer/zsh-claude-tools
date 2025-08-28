#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")"/.. && pwd)"
BIN="${ROOT}/bin/claude-use.zsh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export ZDOTDIR="$tmp"
export CLAUDE_CODE_HOME="$tmp/.claude"
mkdir -p "$CLAUDE_CODE_HOME/envs"

_zsh() {
  zsh -c "
    set -e
    source '$BIN'
    $*
  "
}

echo "== list on empty =="
out="$(_zsh 'claude-use list')"
echo "$out" | grep -q '（空）' || { echo "FAIL: list should be empty"; exit 1; }

echo "== new foo =="
_zsh 'claude-use new foo' </dev/null || true
test -f "$CLAUDE_CODE_HOME/envs/foo.env" || { echo "FAIL: foo.env not created"; exit 1; }

echo "== edit bar (autocreate) =="
rm -f "$CLAUDE_CODE_HOME/envs/bar.env"
_zsh 'claude-use edit bar' </dev/null || true
test -f "$CLAUDE_CODE_HOME/envs/bar.env" || { echo "FAIL: bar.env not created"; exit 1; }

echo "== switch foo =="
echo 'export ANTHROPIC_BASE_URL="https://x.example.com"' >> "$CLAUDE_CODE_HOME/envs/foo.env"
_zsh 'claude-use foo ; [[ "$ANTHROPIC_BASE_URL" == "https://x.example.com" ]]' || { echo "FAIL: switch foo"; exit 1; }

echo "== del reject =="
ret=0
( echo "no" | _zsh 'claude-use del foo' ) || ret=$?
test $ret -eq 0 || { echo "FAIL: del reject should not fail"; exit 1; }
test -f "$CLAUDE_CODE_HOME/envs/foo.env" || { echo "FAIL: foo.env should remain"; exit 1; }

echo "== del yes =="
( echo "yes" | _zsh 'claude-use del foo' )
test ! -f "$CLAUDE_CODE_HOME/envs/foo.env" || { echo "FAIL: foo.env should be deleted"; exit 1; }

echo "== all pass =="
