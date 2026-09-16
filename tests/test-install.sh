#!/usr/bin/env bash
# Tests for install.sh failure branches. Never installs anything.
# Run from anywhere: tests/test-install.sh
set -u

here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
install="$here/../install.sh"
failed=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failed=1; }
skip() { echo "SKIP: $1"; }

make_bin() {
  local dir=$1; shift
  local c
  for c in "$@"; do
    ln -sf "$(command -v "$c")" "$dir/$c" || return 1
  done
}
base=(bash cat echo mktemp rm readlink dirname)

# Test 1: uv missing -> exit 1, prints the uv install hint
bin=$(mktemp -d)
make_bin "$bin" "${base[@]}"
err=$(PATH="$bin" bash "$install" 2>&1 >/dev/null); rc=$?
if [ $rc -ne 0 ] && [[ "$err" == *"astral.sh/uv/install.sh"* ]]; then
  pass "missing uv exits non-zero with install hint"
else
  fail "missing uv: rc=$rc stderr=$err"
fi
rm -rf "$bin"

# Test 2: uv and edge-tts present, mpv missing -> exit 1, prints mpv hint.
# Guarded: if edge-tts is absent the script would run 'uv tool install'.
if command -v uv >/dev/null 2>&1 && command -v edge-tts >/dev/null 2>&1; then
  bin=$(mktemp -d)
  make_bin "$bin" "${base[@]}" uv edge-tts
  err=$(PATH="$bin" bash "$install" 2>&1 >/dev/null); rc=$?
  if [ $rc -ne 0 ] && [[ "$err" == *"mpv is missing"* ]]; then
    pass "missing mpv exits non-zero with package hint"
  else
    fail "missing mpv: rc=$rc stderr=$err"
  fi
  rm -rf "$bin"
else
  skip "missing mpv test needs uv and edge-tts installed"
fi

exit $failed
