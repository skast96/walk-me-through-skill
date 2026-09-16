#!/usr/bin/env bash
# speak.sh: read text on stdin, synthesize it with edge-tts, play it with mpv.
# Blocks until playback ends. Exit 0 on success, 1 with a reason on stderr otherwise.
# Env: WALK_ME_THROUGH_VOICE (edge-tts voice name), WALK_ME_THROUGH_RATE (e.g. +10%).
set -u

voice="${WALK_ME_THROUGH_VOICE:-en-US-AndrewMultilingualNeural}"
rate="${WALK_ME_THROUGH_RATE:-+0%}"

for cmd in edge-tts mpv; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "speak.sh: $cmd not found. Run install.sh in the skill directory." >&2
    exit 1
  fi
done

text_file=$(mktemp) || { echo "speak.sh: mktemp failed" >&2; exit 1; }
audio_file="$text_file.mp3"
trap 'rm -f "$text_file" "$audio_file"' EXIT

cat > "$text_file"
if [ ! -s "$text_file" ]; then
  echo "speak.sh: no text on stdin" >&2
  exit 1
fi

if ! edge-tts --voice "$voice" --rate "$rate" --file "$text_file" --write-media "$audio_file" >/dev/null 2>&1; then
  echo "speak.sh: edge-tts failed. Check network access and the voice name '$voice'." >&2
  exit 1
fi

mpv --no-video --really-quiet "$audio_file" </dev/null
