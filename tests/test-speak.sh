#!/usr/bin/env bash
# Tests for speak.sh. Run from anywhere: tests/test-speak.sh
# Each test builds a PATH that contains only the commands it wants visible.
set -u

here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
speak="$here/../speak.sh"
failed=0
# The tests below assume the edge engine unless they set WALK_ME_THROUGH_TTS themselves.
export WALK_ME_THROUGH_TTS=edge
unset WALK_ME_THROUGH_VOICE WALK_ME_THROUGH_RATE

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
printf '#!/usr/bin/env bash\nexit 0\n' > "$bin/mpv"
chmod +x "$bin/mpv"
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

# Test 6: output path given -> mp3 written there, kept, temp dir empty. Audible. Needs network.
if [ $have_edge -eq 1 ] && [ $have_mpv -eq 1 ]; then
  tmp=$(mktemp -d); out=$(mktemp -d)
  echo "Saved audio test." | TMPDIR="$tmp" bash "$speak" "$out/sub/01-test"; rc=$?
  left=$(ls -A "$tmp" | wc -l)
  if [ $rc -eq 0 ] && [ -s "$out/sub/01-test.mp3" ] && [ "$left" -eq 0 ]; then
    pass "writes the mp3 to the output path and cleans up temp files"
  else
    fail "output path: rc=$rc file_exists=$([ -s "$out/sub/01-test.mp3" ] && echo yes || echo no) leftover=$left"
  fi
  rm -rf "$tmp" "$out"
else
  skip "output path test needs edge-tts and mpv"
fi

# Test 7: output file already exists -> played without synthesis, so no edge-tts needed. Fake mpv.
bin=$(mktemp -d); out=$(mktemp -d)
make_bin "$bin" "${base[@]}"
printf '#!/usr/bin/env bash\nexit 0\n' > "$bin/mpv"
chmod +x "$bin/mpv"
printf 'not really audio' > "$out/existing.mp3"
err=$(echo "ignored" | PATH="$bin" bash "$speak" "$out/existing" 2>&1 >/dev/null); rc=$?
if [ $rc -eq 0 ]; then
  pass "existing output file is replayed without edge-tts"
else
  fail "existing file replay: rc=$rc stderr=$err"
fi
rm -rf "$bin" "$out"

# make_curl DIR LOG BASE : write a fake curl into DIR that plays a server at BASE.
# It appends its arguments to LOG. Requests to any other base URL fail like an unreachable server.
# /health succeeds. /v1/audio/speech writes the -d payload to LOG.body and a fake mp3 to the -o path.
# /tts writes a fake wav to the -o path.
make_curl() {
  cat > "$1/curl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$2"
out=""; data=""; url=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    -o) out=\$2; shift ;;
    -d) data=\$2; shift ;;
    http*) url=\$1 ;;
  esac
  shift
done
case "\$url" in
  "$3"/health) exit 0 ;;
  "$3"/v1/audio/speech) printf '%s' "\$data" > "$2.body"; printf 'fake mp3' > "\$out"; exit 0 ;;
  "$3"/tts) printf 'fake wav' > "\$out"; exit 0 ;;
esac
exit 7
EOF
  chmod +x "$1/curl"
}

# Test 8: unknown engine -> exit 1, reason names the variable. Fake mpv.
bin=$(mktemp -d)
make_bin "$bin" "${base[@]}"
printf '#!/usr/bin/env bash\nexit 0\n' > "$bin/mpv"; chmod +x "$bin/mpv"
err=$(echo "hello" | WALK_ME_THROUGH_TTS=bogus PATH="$bin" bash "$speak" 2>&1 >/dev/null); rc=$?
if [ $rc -ne 0 ] && [[ "$err" == *"WALK_ME_THROUGH_TTS is 'bogus'"* ]]; then
  pass "unknown engine exits non-zero with reason"
else
  fail "unknown engine: rc=$rc stderr=$err"
fi
rm -rf "$bin"

# Test 9: kokoro chosen, curl missing -> exit 1, reason on stderr. Fake mpv.
bin=$(mktemp -d)
make_bin "$bin" "${base[@]}"
printf '#!/usr/bin/env bash\nexit 0\n' > "$bin/mpv"; chmod +x "$bin/mpv"
err=$(echo "hello" | WALK_ME_THROUGH_TTS=kokoro PATH="$bin" bash "$speak" 2>&1 >/dev/null); rc=$?
if [ $rc -ne 0 ] && [[ "$err" == *"curl not found"* ]]; then
  pass "kokoro without curl exits non-zero with reason"
else
  fail "kokoro without curl: rc=$rc stderr=$err"
fi
rm -rf "$bin"

# Test 10: kokoro chosen, server unreachable -> exit 1, reason names the URL, no edge-tts fallback.
# The fake curl serves another port, so the kokoro port is a server that is down.
bin=$(mktemp -d); log=$(mktemp)
make_bin "$bin" "${base[@]}"
printf '#!/usr/bin/env bash\nexit 0\n' > "$bin/mpv"; chmod +x "$bin/mpv"
make_curl "$bin" "$log" "http://localhost:1"
printf '#!/usr/bin/env bash\necho "edge-tts must not run" >&2\nexit 9\n' > "$bin/edge-tts"; chmod +x "$bin/edge-tts"
err=$(echo "hello" | WALK_ME_THROUGH_TTS=kokoro PATH="$bin" bash "$speak" 2>&1 >/dev/null); rc=$?
if [ $rc -ne 0 ] && [[ "$err" == *"kokoro is not answering at http://localhost:8880"* ]] && [[ "$err" != *"edge-tts must not run"* ]]; then
  pass "unreachable kokoro exits non-zero with the URL and does not fall back"
else
  fail "unreachable kokoro: rc=$rc stderr=$err"
fi
rm -rf "$bin" "$log" "$log.body"

# Test 11: kokoro success -> mp3 written, request carries voice, speed and escaped text. Fake curl and mpv.
# The rate has a leading zero on purpose: it must become speed 1.08, not an octal error.
bin=$(mktemp -d); log=$(mktemp); out=$(mktemp -d)
make_bin "$bin" "${base[@]}" mkdir
printf '#!/usr/bin/env bash\nexit 0\n' > "$bin/mpv"; chmod +x "$bin/mpv"
make_curl "$bin" "$log" "http://localhost:8880"
printf 'say "hi"\nthere\n' | WALK_ME_THROUGH_TTS=kokoro WALK_ME_THROUGH_RATE="+08%" PATH="$bin" bash "$speak" "$out/01-test" 2>"$log.err"; rc=$?
body=$(cat "$log.body" 2>/dev/null)
if [ $rc -eq 0 ] && [ -s "$out/01-test.mp3" ] \
   && grep -q "http://localhost:8880/health" "$log" \
   && [[ "$body" == *'"voice":"af_heart"'* ]] && [[ "$body" == *'"speed":1.08'* ]] \
   && [[ "$body" == *'"input":"say \"hi\"\nthere"'* ]]; then
  pass "kokoro writes the mp3 and sends voice, speed and escaped text"
else
  fail "kokoro success: rc=$rc file=$([ -s "$out/01-test.mp3" ] && echo yes || echo no) body=$body stderr=$(cat "$log.err")"
fi
rm -rf "$bin" "$log" "$log.body" "$log.err" "$out"

# Test 12: kokoro with a rate that is not a whole percent -> exit 1, reason names the variable, no request sent.
bin=$(mktemp -d); log=$(mktemp)
make_bin "$bin" "${base[@]}"
printf '#!/usr/bin/env bash\nexit 0\n' > "$bin/mpv"; chmod +x "$bin/mpv"
make_curl "$bin" "$log" "http://localhost:8880"
err=$(echo "hello" | WALK_ME_THROUGH_TTS=kokoro WALK_ME_THROUGH_RATE="+2.5%" PATH="$bin" bash "$speak" 2>&1 >/dev/null); rc=$?
if [ $rc -ne 0 ] && [[ "$err" == *"Kokoro needs a whole percent"* ]] && [ ! -e "$log.body" ]; then
  pass "kokoro rejects a rate that is not a whole percent"
else
  fail "kokoro bad rate: rc=$rc stderr=$err body_sent=$([ -e "$log.body" ] && echo yes || echo no)"
fi
rm -rf "$bin" "$log" "$log.body"

# Test 13: pocket success -> wav written next to the given path, text sent as a form field from the file, voice field set.
bin=$(mktemp -d); log=$(mktemp); out=$(mktemp -d)
make_bin "$bin" "${base[@]}" mkdir
printf '#!/usr/bin/env bash\nexit 0\n' > "$bin/mpv"; chmod +x "$bin/mpv"
make_curl "$bin" "$log" "http://localhost:8000"
echo "hello pocket" | WALK_ME_THROUGH_TTS=pocket WALK_ME_THROUGH_VOICE=marius PATH="$bin" bash "$speak" "$out/01-test" 2>"$log.err"; rc=$?
if [ $rc -eq 0 ] && [ -s "$out/01-test.wav" ] && [ ! -e "$out/01-test.mp3" ] \
   && grep -q "http://localhost:8000/tts -F text=<" "$log" && grep -q -- "-F voice_url=marius" "$log"; then
  pass "pocket writes a wav and posts text and voice as form fields"
else
  fail "pocket success: rc=$rc ls=$(ls "$out") log=$(cat "$log") stderr=$(cat "$log.err")"
fi
rm -rf "$bin" "$log" "$log.err" "$out"

# Test 14: pocket without a voice -> no voice_url field, the server default is used.
bin=$(mktemp -d); log=$(mktemp); out=$(mktemp -d)
make_bin "$bin" "${base[@]}" mkdir
printf '#!/usr/bin/env bash\nexit 0\n' > "$bin/mpv"; chmod +x "$bin/mpv"
make_curl "$bin" "$log" "http://localhost:8000"
echo "hello pocket" | WALK_ME_THROUGH_TTS=pocket PATH="$bin" bash "$speak" "$out/01-test" 2>"$log.err"; rc=$?
if [ $rc -eq 0 ] && [ -s "$out/01-test.wav" ] && ! grep -q "voice_url" "$log"; then
  pass "pocket without a voice sends no voice field"
else
  fail "pocket default voice: rc=$rc log=$(cat "$log") stderr=$(cat "$log.err")"
fi
rm -rf "$bin" "$log" "$log.err" "$out"

exit $failed
