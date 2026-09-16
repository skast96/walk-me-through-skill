#!/usr/bin/env bash
# speak.sh: read text on stdin, synthesize it with the configured engine, play it with mpv.
# Blocks until playback ends. Exit 0 on success, 1 with a reason on stderr otherwise.
# Usage: speak.sh [OUTPUT.mp3]
#   Without OUTPUT the audio goes to a temp file that is removed afterwards.
#   With OUTPUT the mp3 is written there and kept. If OUTPUT already exists it is
#   played as is and stdin is ignored, so a repeat needs no synthesis.
# Env: WALK_ME_THROUGH_TTS         edge (default) or kokoro. No fallback between them.
#      WALK_ME_THROUGH_VOICE       voice name for the chosen engine
#      WALK_ME_THROUGH_RATE        whole percent, e.g. +10%. Kokoro gets it as speed 1.10.
#      WALK_ME_THROUGH_KOKORO_URL  base URL of a Kokoro-FastAPI server, default http://localhost:8880
set -u
engine="${WALK_ME_THROUGH_TTS:-edge}"
rate="${WALK_ME_THROUGH_RATE:-+0%}"
kokoro_url="${WALK_ME_THROUGH_KOKORO_URL:-http://localhost:8880}"
case "$engine" in
  edge)   voice="${WALK_ME_THROUGH_VOICE:-en-US-AndrewMultilingualNeural}" ;;
  kokoro) voice="${WALK_ME_THROUGH_VOICE:-af_heart}" ;;
  *)
    echo "speak.sh: WALK_ME_THROUGH_TTS is '$engine'. Use 'edge' or 'kokoro'." >&2; exit 1 ;;
esac
output="${1:-}"

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
      echo "speak.sh: curl not found. It is needed to talk to Kokoro." >&2; exit 1
    fi
    if ! curl -sf --max-time 2 "$kokoro_url/health" >/dev/null 2>&1; then
      echo "speak.sh: Kokoro is not reachable at $kokoro_url. Start the FastKoko container or set WALK_ME_THROUGH_KOKORO_URL." >&2; exit 1
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
  pct=${rate%\%}; pct=${pct#+}
  if ! [[ "$pct" =~ ^-?[0-9]+$ ]]; then
    echo "speak.sh: WALK_ME_THROUGH_RATE is '$rate'. Kokoro needs a whole percent such as +10%." >&2
    return 1
  fi
  speed=$(( (100 + pct) / 100 )).$(printf '%02d' $(( (100 + pct) % 100 )))
  if ! err=$(curl -sfS --max-time 300 -X POST "$kokoro_url/v1/audio/speech" \
      -H 'Content-Type: application/json' \
      -d "{\"model\":\"kokoro\",\"input\":\"$text\",\"voice\":\"$voice\",\"response_format\":\"mp3\",\"speed\":$speed}" \
      -o "$2" 2>&1); then
    echo "speak.sh: Kokoro at $kokoro_url failed to synthesize. Check the voice name '$voice'. ${err##*$'\n'}" >&2
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
    audio_file="$text_file.mp3"
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
