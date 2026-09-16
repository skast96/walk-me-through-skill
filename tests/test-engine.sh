#!/usr/bin/env bash
# Tests for engine.sh. Run from anywhere: tests/test-engine.sh
# Docker and curl are fakes that record their arguments. No container is ever started.
set -u

here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
engine="$here/../engine.sh"
failed=0
unset WALK_ME_THROUGH_TTS

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failed=1; }

make_bin() {
  local dir=$1; shift
  local c
  for c in "$@"; do
    ln -sf "$(command -v "$c")" "$dir/$c" || return 1
  done
}
base=(bash cat readlink dirname)

# make_fakes DIR LOG READY : fake docker, curl and sleep in DIR.
# docker appends its arguments to LOG. 'docker ps' prints an id only if the file DIR/running exists.
# curl succeeds only if the file READY exists. sleep returns at once so the wait loop spins fast.
make_fakes() {
  cat > "$1/docker" <<FAKE
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$2"
case "\$1" in
  ps) [ -e "$1/running" ] && echo abc123 ;;
  run) echo abc123 ;;
  logs) echo "fake log line" ;;
esac
exit 0
FAKE
  cat > "$1/curl" <<FAKE
#!/usr/bin/env bash
[ -e "$3" ]
FAKE
  printf '#!/usr/bin/env bash\nexit 0\n' > "$1/sleep"
  chmod +x "$1/docker" "$1/curl" "$1/sleep"
}

# Test 1: edge -> start and stop exit 0 without docker on PATH
bin=$(mktemp -d)
make_bin "$bin" "${base[@]}"
PATH="$bin" bash "$engine" start; rc1=$?
PATH="$bin" bash "$engine" stop; rc2=$?
if [ $rc1 -eq 0 ] && [ $rc2 -eq 0 ]; then
  pass "edge start and stop are no-ops"
else
  fail "edge: start rc=$rc1 stop rc=$rc2"
fi
rm -rf "$bin"

# Test 2: unknown engine -> exit 1, reason names the variable
bin=$(mktemp -d)
make_bin "$bin" "${base[@]}"
err=$(WALK_ME_THROUGH_TTS=bogus PATH="$bin" bash "$engine" start 2>&1 >/dev/null); rc=$?
if [ $rc -ne 0 ] && [[ "$err" == *"WALK_ME_THROUGH_TTS is 'bogus'"* ]]; then
  pass "unknown engine exits non-zero with reason"
else
  fail "unknown engine: rc=$rc stderr=$err"
fi
rm -rf "$bin"

# Test 3: unknown action -> exit 1 with usage
bin=$(mktemp -d)
make_bin "$bin" "${base[@]}"
err=$(WALK_ME_THROUGH_TTS=kokoro PATH="$bin" bash "$engine" restart 2>&1 >/dev/null); rc=$?
if [ $rc -ne 0 ] && [[ "$err" == *"usage"* ]]; then
  pass "unknown action exits non-zero with usage"
else
  fail "unknown action: rc=$rc stderr=$err"
fi
rm -rf "$bin"

# Test 4: kokoro start without docker -> exit 1 with reason
bin=$(mktemp -d)
make_bin "$bin" "${base[@]}"
err=$(WALK_ME_THROUGH_TTS=kokoro PATH="$bin" bash "$engine" start 2>&1 >/dev/null); rc=$?
if [ $rc -ne 0 ] && [[ "$err" == *"docker not found"* ]]; then
  pass "kokoro start without docker exits non-zero with reason"
else
  fail "kokoro without docker: rc=$rc stderr=$err"
fi
rm -rf "$bin"

# Test 5: kokoro start, container not running, health answers -> docker run with image and port, exit 0
bin=$(mktemp -d); log=$(mktemp); ready=$(mktemp)
make_bin "$bin" "${base[@]}"
make_fakes "$bin" "$log" "$ready"
err=$(WALK_ME_THROUGH_TTS=kokoro PATH="$bin" bash "$engine" start 2>&1 >/dev/null); rc=$?
if [ $rc -eq 0 ] && grep -q "^run -d --rm --name walk-me-through-kokoro -p 8880:8880 ghcr.io/remsky/kokoro-fastapi-cpu:latest$" "$log"; then
  pass "kokoro start runs the container and waits for health"
else
  fail "kokoro start: rc=$rc stderr=$err log=$(cat "$log")"
fi
rm -rf "$bin" "$log" "$ready"

# Test 6: kokoro start, container already running -> no docker run, exit 0
bin=$(mktemp -d); log=$(mktemp); ready=$(mktemp)
make_bin "$bin" "${base[@]}"
make_fakes "$bin" "$log" "$ready"
touch "$bin/running"
err=$(WALK_ME_THROUGH_TTS=kokoro PATH="$bin" bash "$engine" start 2>&1 >/dev/null); rc=$?
if [ $rc -eq 0 ] && ! grep -q "^run " "$log"; then
  pass "kokoro start reuses a running container"
else
  fail "kokoro reuse: rc=$rc stderr=$err log=$(cat "$log")"
fi
rm -rf "$bin" "$log" "$ready"

# Test 7: pocket start, health never answers -> container stopped, exit 1 naming the wait. Volume and port in run args.
bin=$(mktemp -d); log=$(mktemp)
make_bin "$bin" "${base[@]}"
make_fakes "$bin" "$log" "$bin/never-ready"
err=$(WALK_ME_THROUGH_TTS=pocket PATH="$bin" bash "$engine" start 2>&1 >/dev/null); rc=$?
if [ $rc -ne 0 ] && [[ "$err" == *"within 300 seconds"* ]] && [[ "$err" == *"fake log line"* ]] \
   && grep -q "^run -d --rm --name walk-me-through-pocket -p 8000:8000 -v walk-me-through-pocket-cache:/root/.cache walk-me-through-pocket$" "$log" \
   && grep -q "^stop walk-me-through-pocket$" "$log"; then
  pass "pocket start times out, stops the container and reports"
else
  fail "pocket timeout: rc=$rc stderr=$err log=$(cat "$log")"
fi
rm -rf "$bin" "$log"

# Test 8: kokoro stop -> docker stop called, exit 0
bin=$(mktemp -d); log=$(mktemp)
make_bin "$bin" "${base[@]}"
make_fakes "$bin" "$log" "$bin/never-ready"
WALK_ME_THROUGH_TTS=kokoro PATH="$bin" bash "$engine" stop; rc=$?
if [ $rc -eq 0 ] && grep -q "^stop walk-me-through-kokoro$" "$log"; then
  pass "kokoro stop stops the container"
else
  fail "kokoro stop: rc=$rc log=$(cat "$log")"
fi
rm -rf "$bin" "$log"

exit $failed
