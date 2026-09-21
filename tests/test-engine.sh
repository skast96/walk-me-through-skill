#!/usr/bin/env bash
# Tests for engine.sh. Run from anywhere: tests/test-engine.sh
# Docker, curl, sleep and date are fakes. No container is ever started and no test waits.
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
base=(bash cat readlink dirname rm touch)

# make_fakes DIR LOG READY : fake docker, curl, sleep and date in DIR.
# docker appends its arguments to LOG. 'docker ps' prints an id only if the file DIR/running exists.
# 'docker run' creates that file unless DIR/crash exists, which plays a container that exits at once.
# curl succeeds only if the file READY exists. sleep returns at once.
# date advances 200 fake seconds per call, so the 300 second deadline passes on the second loop check.
make_fakes() {
  cat > "$1/docker" <<FAKE
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$2"
case "\$1" in
  ps) [ -e "$1/running" ] && echo abc123 ;;
  run) [ -e "$1/crash" ] || touch "$1/running"; echo abc123 ;;
  rm) rm -f "$1/running" ;;
  logs) echo "fake log line" ;;
esac
exit 0
FAKE
  cat > "$1/curl" <<FAKE
#!/usr/bin/env bash
[ -e "$3" ]
FAKE
  cat > "$1/date" <<FAKE
#!/usr/bin/env bash
n=\$(( \$(cat "$1/clock" 2>/dev/null || echo 1000) + 200 ))
echo "\$n" > "$1/clock"
echo "\$n"
FAKE
  printf '#!/usr/bin/env bash\nexit 0\n' > "$1/sleep"
  chmod +x "$1/docker" "$1/curl" "$1/date" "$1/sleep"
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
if [ $rc -eq 0 ] && grep -q "^run -d --name walk-me-through-kokoro -p 127.0.0.1:8880:8880 ghcr.io/remsky/kokoro-fastapi-cpu:latest$" "$log"; then
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

# Test 7: pocket start, health never answers -> container removed, exit 1 naming the wait and the logs.
# Volume and localhost port in the run args.
bin=$(mktemp -d); log=$(mktemp)
make_bin "$bin" "${base[@]}"
make_fakes "$bin" "$log" "$bin/never-ready"
err=$(WALK_ME_THROUGH_TTS=pocket PATH="$bin" bash "$engine" start 2>&1 >/dev/null); rc=$?
if [ $rc -ne 0 ] && [[ "$err" == *"within 300 seconds"* ]] && [[ "$err" == *"fake log line"* ]] \
   && grep -q "^run -d --name walk-me-through-pocket -p 127.0.0.1:8000:8000 -v walk-me-through-pocket-cache:/root/.cache walk-me-through-pocket$" "$log" \
   && grep -q "^rm -f walk-me-through-pocket$" "$log"; then
  pass "pocket start times out, removes the container and reports"
else
  fail "pocket timeout: rc=$rc stderr=$err log=$(cat "$log")"
fi
rm -rf "$bin" "$log"

# Test 8: kokoro start, container exits right after starting -> exit 1 at once with the logs, no wait.
bin=$(mktemp -d); log=$(mktemp)
make_bin "$bin" "${base[@]}"
make_fakes "$bin" "$log" "$bin/never-ready"
touch "$bin/crash"
err=$(WALK_ME_THROUGH_TTS=kokoro PATH="$bin" bash "$engine" start 2>&1 >/dev/null); rc=$?
if [ $rc -ne 0 ] && [[ "$err" == *"stopped on its own"* ]] && [[ "$err" == *"fake log line"* ]] \
   && [ "$(grep -c '^ps ' "$log")" -eq 2 ]; then
  pass "a container that exits early fails at once with its logs"
else
  fail "early exit: rc=$rc stderr=$err log=$(cat "$log")"
fi
rm -rf "$bin" "$log"

# Test 9: kokoro stop -> docker rm -f called, exit 0
bin=$(mktemp -d); log=$(mktemp)
make_bin "$bin" "${base[@]}"
make_fakes "$bin" "$log" "$bin/never-ready"
WALK_ME_THROUGH_TTS=kokoro PATH="$bin" bash "$engine" stop; rc=$?
if [ $rc -eq 0 ] && grep -q "^rm -f walk-me-through-kokoro$" "$log"; then
  pass "kokoro stop removes the container"
else
  fail "kokoro stop: rc=$rc log=$(cat "$log")"
fi
rm -rf "$bin" "$log"

# Test 10: stop with an unknown engine -> exit 0, so the skill's last step never fails
bin=$(mktemp -d)
make_bin "$bin" "${base[@]}"
WALK_ME_THROUGH_TTS=bogus PATH="$bin" bash "$engine" stop 2>/dev/null; rc=$?
if [ $rc -eq 0 ]; then
  pass "stop with an unknown engine exits 0"
else
  fail "stop unknown engine: rc=$rc"
fi
rm -rf "$bin"

exit $failed
