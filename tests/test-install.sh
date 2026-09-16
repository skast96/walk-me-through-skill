#!/usr/bin/env bash
# Tests for install.sh failure branches. Never installs anything.
# Run from anywhere: tests/test-install.sh
set -u

here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
install="$here/../install.sh"
failed=0
# The tests below assume the edge engine unless they set WALK_ME_THROUGH_TTS themselves.
export WALK_ME_THROUGH_TTS=edge
unset WALK_ME_THROUGH_VOICE WALK_ME_THROUGH_RATE WALK_ME_THROUGH_KOKORO_URL

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

# Test 3: kokoro chosen, server unreachable -> exit 1, prints the URL. Fake curl that always fails.
bin=$(mktemp -d)
make_bin "$bin" "${base[@]}"
printf '#!/usr/bin/env bash\nexit 7\n' > "$bin/curl"; chmod +x "$bin/curl"
err=$(WALK_ME_THROUGH_TTS=kokoro WALK_ME_THROUGH_KOKORO_URL="http://fake:8880" PATH="$bin" bash "$install" 2>&1 >/dev/null); rc=$?
if [ $rc -ne 0 ] && [[ "$err" == *"Kokoro is not reachable at http://fake:8880"* ]]; then
  pass "unreachable kokoro exits non-zero with the URL"
else
  fail "unreachable kokoro: rc=$rc stderr=$err"
fi
rm -rf "$bin"

# Test 4: unknown engine -> exit 1, names the variable
bin=$(mktemp -d)
make_bin "$bin" "${base[@]}"
err=$(WALK_ME_THROUGH_TTS=bogus PATH="$bin" bash "$install" 2>&1 >/dev/null); rc=$?
if [ $rc -ne 0 ] && [[ "$err" == *"WALK_ME_THROUGH_TTS is 'bogus'"* ]]; then
  pass "unknown engine exits non-zero with reason"
else
  fail "unknown engine: rc=$rc stderr=$err"
fi
rm -rf "$bin"

exit $failed
