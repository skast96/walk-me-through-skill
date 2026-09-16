#!/usr/bin/env bash
# install.sh: install what speak.sh needs and speak one test sentence.
# Safe to run more than once. Exit 0 on success, 1 with instructions otherwise.
set -u

here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)

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

if ! command -v mpv >/dev/null 2>&1; then
  echo "mpv is missing. Install it with your package manager, then rerun this script:" >&2
  echo "  sudo pacman -S mpv      (Arch)" >&2
  echo "  sudo apt install mpv    (Debian, Ubuntu)" >&2
  echo "  brew install mpv        (macOS)" >&2
  exit 1
fi

echo "Speaking a test sentence..."
if ! echo "Walk me through is installed. Restart Claude Code, then run slash walk me through on a plan." | "$here/speak.sh"; then
  echo "The test sentence failed. Check network access and audio output, then rerun this script." >&2
  exit 1
fi

echo "Done. Restart Claude Code so the walk-me-through skill is picked up."
