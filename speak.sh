#!/usr/bin/env bash
# speak.sh: read text on stdin, synthesize it with the configured engine, play it with mpv.
# Blocks until playback ends. Exit 0 on success, 1 with a reason on stderr otherwise.
# Usage: speak.sh [OUTPUT]
#   OUTPUT is a path without extension. The script appends .mp3 (edge, kokoro) or .wav (pocket).
#   Without OUTPUT the audio goes to a temp file that is removed afterwards.
#   With OUTPUT the file is written there and kept. If it already exists it is
#   played as is and stdin is ignored, so a repeat needs no synthesis.
# Env: WALK_ME_THROUGH_TTS    edge (default), kokoro or pocket. No fallback between them.
#      WALK_ME_THROUGH_VOICE  voice name for the chosen engine
#      WALK_ME_THROUGH_RATE   whole percent, e.g. +10%. Kokoro gets it as speed 1.10. Pocket ignores it.
# kokoro and pocket talk to the container that engine.sh starts, on a fixed local port.
set -u
engine="${WALK_ME_THROUGH_TTS:-edge}"
rate="${WALK_ME_THROUGH_RATE:-+0%}"
case "$engine" in
  edge)
    voice="${WALK_ME_THROUGH_VOICE:-en-US-AndrewMultilingualNeural}"
    ext=mp3 ;;
  kokoro)
    voice="${WALK_ME_THROUGH_VOICE:-af_heart}"
    url="http://localhost:8880"
    ext=mp3 ;;
  pocket)
    voice="${WALK_ME_THROUGH_VOICE:-}"
    url="http://localhost:8000"
    ext=wav ;;
  *)
    echo "speak.sh: WALK_ME_THROUGH_TTS is '$engine'. Use 'edge', 'kokoro' or 'pocket'." >&2; exit 1 ;;
esac
output="${1:-}"
[ -n "$output" ] && output="$output.$ext"

if ! command -v mpv >/dev/null 2>&1; then
  echo "speak.sh: mpv not found. Run install.sh in the skill directory." >&2; exit 1
fi

# Checks the engine's tools are present. Prints a reason and exits 1 otherwise.
check_engine() {
  if [ "$engine" = edge ]; then
    if ! command -v edge-tts >/dev/null 2>&1; then
      echo "speak.sh: edge-tts not found. Run install.sh in the skill directory." >&2; exit 1
    fi
  else
    if ! command -v curl >/dev/null 2>&1; then
      echo "speak.sh: curl not found. It is needed to talk to $engine." >&2; exit 1
    fi
    if ! curl -sf --max-time 2 "$url/health" >/dev/null 2>&1; then
      echo "speak.sh: $engine is not answering at $url. Run engine.sh start in the skill directory." >&2; exit 1
    fi
  fi
}

# synth_edge TEXT_FILE AUDIO_FILE
synth_edge() {
  local err
  if ! err=$(edge-tts --voice "$voice" --rate "$rate" --file "$1" --write-media "$2" 2>&1 >/dev/null); then
    echo "speak.sh: edge-tts failed. Check network access and the voice name '$voice'. ${err##*$'\n'}" >&2
    return 1
  fi
}

# synth_kokoro TEXT_FILE AUDIO_FILE
synth_kokoro() {
  local text speed pct err
  text=$(cat "$1")
  text=${text//\\/\\\\}
  text=${text//\"/\\\"}
  text=${text//$'\n'/\\n}
  text=${text//$'\r'/\\r}
  text=${text//$'\t'/\\t}
  # Sign, digits, percent. Leading zeros are dropped so bash does not read them as octal.
  if ! [[ "$rate" =~ ^([+-]?)0*([0-9]+)%$ ]]; then
    echo "speak.sh: WALK_ME_THROUGH_RATE is '$rate'. Kokoro needs a whole percent such as +10%." >&2
    return 1
  fi
  pct="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
  speed=$(( (100 + pct) / 100 )).$(printf '%02d' $(( (100 + pct) % 100 )))
  if ! err=$(curl -sfS --max-time 300 -X POST "$url/v1/audio/speech" \
      -H 'Content-Type: application/json' \
      -d "{\"model\":\"kokoro\",\"input\":\"$text\",\"voice\":\"$voice\",\"response_format\":\"mp3\",\"speed\":$speed}" \
      -o "$2" 2>&1); then
    echo "speak.sh: kokoro at $url failed to synthesize. Check the voice name '$voice'. ${err##*$'\n'}" >&2
    return 1
  fi
}

# synth_pocket TEXT_FILE AUDIO_FILE
synth_pocket() {
  local err voice_args=()
  [ -n "$voice" ] && voice_args=(-F "voice_url=$voice")
  if ! err=$(curl -sfS --max-time 300 -X POST "$url/tts" -F "text=<$1" ${voice_args[@]+"${voice_args[@]}"} -o "$2" 2>&1); then
    echo "speak.sh: pocket at $url failed to synthesize. Check the voice name '$voice'. ${err##*$'\n'}" >&2
    return 1
  fi
}

if [ -n "$output" ] && [ -s "$output" ]; then
  audio_file="$output"
else
  check_engine
  text_file=$(mktemp) || { echo "speak.sh: mktemp failed" >&2; exit 1; }
  if [ -n "$output" ]; then
    audio_file="$output"
    if ! mkdir -p "$(dirname "$output")"; then
      echo "speak.sh: cannot create the directory for '$output'." >&2; rm -f "$text_file"; exit 1
    fi
    trap 'rm -f "$text_file"' EXIT
  else
    audio_file="$text_file.$ext"
    trap 'rm -f "$text_file" "$audio_file"' EXIT
  fi
  cat > "$text_file"
  if [ ! -s "$text_file" ]; then
    echo "speak.sh: no text on stdin" >&2; exit 1
  fi
  if ! "synth_$engine" "$text_file" "$audio_file"; then
    rm -f "$audio_file"; exit 1
  fi
fi

if ! mpv --no-video --really-quiet "$audio_file" </dev/null; then
  echo "speak.sh: mpv failed to play the audio. Check the audio output." >&2; exit 1
fi
