#!/usr/bin/env bash
# install.sh: install what speak.sh needs for the configured engine and speak one test sentence.
# Safe to run more than once. Exit 0 on success, 1 with instructions otherwise.
# Env: WALK_ME_THROUGH_TTS edge (default) or kokoro, WALK_ME_THROUGH_KOKORO_URL.
set -u

here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
engine="${WALK_ME_THROUGH_TTS:-edge}"
kokoro_url="${WALK_ME_THROUGH_KOKORO_URL:-http://localhost:8880}"

case "$engine" in
  edge)
    if ! command -v uv >/dev/null 2>&1; then
      echo "uv is missing. Install it, open a new shell, then rerun this script:" >&2
      echo "  curl -LsSf https://astral.sh/uv/install.sh | sh" >&2
      exit 1
    fi
    if ! command -v edge-tts >/dev/null 2>&1; then
      echo "Installing edge-tts as a uv tool..."
      if ! uv tool install edge-tts; then
        echo "uv tool install edge-tts failed. See the output above." >&2
        exit 1
      fi
    fi
    if ! command -v edge-tts >/dev/null 2>&1; then
      echo "edge-tts is installed but not on PATH. Run 'uv tool update-shell', open a new shell, then rerun this script." >&2
      exit 1
    fi
    ;;
  kokoro)
    if ! command -v curl >/dev/null 2>&1; then
      echo "curl is missing. Install it with your package manager, then rerun this script." >&2
      exit 1
    fi
    if ! curl -sf --max-time 2 "$kokoro_url/health" >/dev/null 2>&1; then
      echo "Kokoro is not reachable at $kokoro_url. Start the FastKoko container or set WALK_ME_THROUGH_KOKORO_URL, then rerun this script." >&2
      exit 1
    fi
    echo "Kokoro found at $kokoro_url."
    ;;
  *)
    echo "WALK_ME_THROUGH_TTS is '$engine'. Use 'edge' or 'kokoro'." >&2
    exit 1
    ;;
esac

if ! command -v mpv >/dev/null 2>&1; then
  echo "mpv is missing. Install it with your package manager, then rerun this script:" >&2
  echo "  sudo pacman -S mpv      (Arch)" >&2
  echo "  sudo apt install mpv    (Debian, Ubuntu)" >&2
  echo "  brew install mpv        (macOS)" >&2
  exit 1
fi

echo "Speaking a test sentence with $engine..."
if ! echo "Walk me through is installed. Restart Claude Code, then run slash walk me through on a plan." | "$here/speak.sh"; then
  echo "The test sentence failed. Check the message above and the audio output, then rerun this script." >&2
  exit 1
fi

echo "Done. Restart Claude Code so the walk-me-through skill is picked up."
