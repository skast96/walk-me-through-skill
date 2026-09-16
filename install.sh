#!/usr/bin/env bash
# install.sh: install what the configured engine needs, start it, speak one test sentence, stop it.
# Safe to run more than once. Exit 0 on success, 1 with instructions otherwise.
# Env: WALK_ME_THROUGH_TTS edge (default), kokoro or pocket.
set -u

here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
engine="${WALK_ME_THROUGH_TTS:-edge}"

need_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "docker is missing. Install Docker, make sure your user can run it, then rerun this script." >&2
    exit 1
  fi
  if ! docker info >/dev/null 2>&1; then
    echo "docker is installed but the daemon is not running or not accessible. Fix that, then rerun this script." >&2
    exit 1
  fi
}

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
    need_docker
    echo "Pulling the Kokoro image..."
    if ! docker pull ghcr.io/remsky/kokoro-fastapi-cpu:latest; then
      echo "docker pull failed. See the output above." >&2
      exit 1
    fi
    ;;
  pocket)
    need_docker
    echo "Building the pocket-tts image. This downloads the CPU build of PyTorch once..."
    if ! docker build -t walk-me-through-pocket "$here/docker/pocket"; then
      echo "docker build failed. See the output above." >&2
      exit 1
    fi
    ;;
  *)
    echo "WALK_ME_THROUGH_TTS is '$engine'. Use 'edge', 'kokoro' or 'pocket'." >&2
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

if [ "$engine" != edge ]; then
  echo "Starting the $engine container. The first start of pocket downloads its model and can take a few minutes..."
  if ! "$here/engine.sh" start; then
    exit 1
  fi
fi

echo "Speaking a test sentence with $engine..."
if ! echo "Walk me through is installed. Restart Claude Code, then run slash walk me through on a plan." | "$here/speak.sh"; then
  echo "The test sentence failed. Check the message above and the audio output, then rerun this script." >&2
  "$here/engine.sh" stop
  exit 1
fi
"$here/engine.sh" stop

echo "Done. Restart Claude Code so the walk-me-through skill is picked up."
