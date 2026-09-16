#!/usr/bin/env bash
# Tests for speak.sh. Run from anywhere: tests/test-speak.sh
# Each test builds a PATH that contains only the commands it wants visible.
set -u

here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
speak="$here/../speak.sh"
failed=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failed=1; }
skip() { echo "SKIP: $1"; }

# make_bin DIR CMD... : symlink each CMD into DIR so PATH=DIR exposes only them
make_bin() {
  local dir=$1; shift
  local c
  for c in "$@"; do
    ln -sf "$(command -v "$c")" "$dir/$c" || return 1
  done
}
base=(bash cat mktemp rm readlink dirname)
have_edge=0; command -v edge-tts >/dev/null 2>&1 && have_edge=1
have_mpv=0;  command -v mpv      >/dev/null 2>&1 && have_mpv=1

# Test 1: edge-tts missing -> exit 1, reason on stderr
bin=$(mktemp -d)
make_bin "$bin" "${base[@]}"
[ $have_mpv -eq 1 ] && make_bin "$bin" mpv
err=$(echo "hello" | PATH="$bin" bash "$speak" 2>&1 >/dev/null); rc=$?
if [ $rc -ne 0 ] && [[ "$err" == *"edge-tts not found"* ]]; then
  pass "missing edge-tts exits non-zero with reason"
else
  fail "missing edge-tts: rc=$rc stderr=$err"
fi
rm -rf "$bin"

# Test 2: mpv missing -> exit 1, reason on stderr
if [ $have_edge -eq 1 ]; then
  bin=$(mktemp -d)
  make_bin "$bin" "${base[@]}" edge-tts
  err=$(echo "hello" | PATH="$bin" bash "$speak" 2>&1 >/dev/null); rc=$?
  if [ $rc -ne 0 ] && [[ "$err" == *"mpv not found"* ]]; then
    pass "missing mpv exits non-zero with reason"
  else
    fail "missing mpv: rc=$rc stderr=$err"
  fi
  rm -rf "$bin"
else
  skip "missing mpv test needs edge-tts installed"
fi

# Test 3: empty stdin -> exit 1
if [ $have_edge -eq 1 ] && [ $have_mpv -eq 1 ]; then
  err=$(printf '' | bash "$speak" 2>&1 >/dev/null); rc=$?
  if [ $rc -ne 0 ] && [[ "$err" == *"no text"* ]]; then
    pass "empty stdin exits non-zero"
  else
    fail "empty stdin: rc=$rc stderr=$err"
  fi
else
  skip "empty stdin test needs edge-tts and mpv"
fi

# Test 4: success -> exit 0, temp files removed. Audible. Needs network.
if [ $have_edge -eq 1 ] && [ $have_mpv -eq 1 ]; then
  tmp=$(mktemp -d)
  echo "Speak script test." | TMPDIR="$tmp" bash "$speak"; rc=$?
  left=$(ls -A "$tmp" | wc -l)
  if [ $rc -eq 0 ] && [ "$left" -eq 0 ]; then
    pass "speaks and cleans up temp files"
  else
    fail "success path: rc=$rc leftover files=$left"
  fi
  rm -rf "$tmp"
else
  skip "success test needs edge-tts and mpv"
fi

# Test 5: mpv fails -> exit 1, reason on stderr. Uses a fake mpv. Needs network.
if [ $have_edge -eq 1 ]; then
  bin=$(mktemp -d)
  make_bin "$bin" "${base[@]}" edge-tts
  printf '#!/usr/bin/env bash\nexit 2\n' > "$bin/mpv"
  chmod +x "$bin/mpv"
  err=$(echo "hello" | PATH="$bin:$PATH" bash "$speak" 2>&1 >/dev/null); rc=$?
  if [ $rc -ne 0 ] && [[ "$err" == *"mpv failed"* ]]; then
    pass "mpv failure exits non-zero with reason"
  else
    fail "mpv failure: rc=$rc stderr=$err"
  fi
  rm -rf "$bin"
else
  skip "mpv failure test needs edge-tts installed"
fi

exit $failed
