#!/usr/bin/env bash
# speak.sh: read text on stdin, synthesize it with edge-tts, play it with mpv.
# Blocks until playback ends. Exit 0 on success, 1 with a reason on stderr otherwise.
# Usage: speak.sh [OUTPUT.mp3]
#   Without OUTPUT the audio goes to a temp file that is removed afterwards.
#   With OUTPUT the mp3 is written there and kept. If OUTPUT already exists it is
#   played as is and stdin is ignored, so a repeat needs no synthesis.
# Env: WALK_ME_THROUGH_VOICE (edge-tts voice name), WALK_ME_THROUGH_RATE (e.g. +10%).
set -u

voice="${WALK_ME_THROUGH_VOICE:-en-US-AndrewMultilingualNeural}"
rate="${WALK_ME_THROUGH_RATE:-+0%}"
output="${1:-}"

if ! command -v mpv >/dev/null 2>&1; then
  echo "speak.sh: mpv not found. Run install.sh in the skill directory." >&2
  exit 1
fi

if [ -n "$output" ] && [ -s "$output" ]; then
  audio_file="$output"
else
  if ! command -v edge-tts >/dev/null 2>&1; then
    echo "speak.sh: edge-tts not found. Run install.sh in the skill directory." >&2
    exit 1
  fi

  text_file=$(mktemp) || { echo "speak.sh: mktemp failed" >&2; exit 1; }
  if [ -n "$output" ]; then
    audio_file="$output"
    if ! mkdir -p "$(dirname "$output")"; then
      echo "speak.sh: cannot create the directory for '$output'." >&2
      rm -f "$text_file"
      exit 1
    fi
    trap 'rm -f "$text_file"' EXIT
  else
    audio_file="$text_file.mp3"
    trap 'rm -f "$text_file" "$audio_file"' EXIT
  fi

  cat > "$text_file"
  if [ ! -s "$text_file" ]; then
    echo "speak.sh: no text on stdin" >&2
    exit 1
  fi

  if ! tts_err=$(edge-tts --voice "$voice" --rate "$rate" --file "$text_file" --write-media "$audio_file" 2>&1 >/dev/null); then
    echo "speak.sh: edge-tts failed. Check network access and the voice name '$voice'. ${tts_err##*$'\n'}" >&2
    rm -f "$audio_file"
    exit 1
  fi
fi

if ! mpv --no-video --really-quiet "$audio_file" </dev/null; then
  echo "speak.sh: mpv failed to play the audio. Check the audio output." >&2
  exit 1
fi
