#!/usr/bin/env bash
# engine.sh: start or stop the Docker container of the configured speech engine.
# Usage: engine.sh start|stop
#   start  Makes sure the engine's container runs and answers its health check.
#          Exit 0 when ready, 1 with a reason on stderr otherwise. No-op for edge.
#   stop   Stops and removes the container. Exit 0 even when nothing was running.
# Env: WALK_ME_THROUGH_TTS edge (default), kokoro or pocket.
set -u
engine="${WALK_ME_THROUGH_TTS:-edge}"
action="${1:-}"

case "$action" in
  start|stop) ;;
  *) echo "engine.sh: usage: engine.sh start|stop" >&2; exit 1 ;;
esac

case "$engine" in
  edge) exit 0 ;;
  kokoro)
    image="ghcr.io/remsky/kokoro-fastapi-cpu:latest"
    port=8880
    run_args=() ;;
  pocket)
    image="walk-me-through-pocket"
    port=8000
    run_args=(-v walk-me-through-pocket-cache:/root/.cache) ;;
  *)
    # stop must always succeed, so a misconfigured machine can still clean up.
    [ "$action" = stop ] && exit 0
    echo "engine.sh: WALK_ME_THROUGH_TTS is '$engine'. Use 'edge', 'kokoro' or 'pocket'." >&2; exit 1 ;;
esac
name="walk-me-through-$engine"
url="http://localhost:$port"

if [ "$action" = stop ]; then
  command -v docker >/dev/null 2>&1 || exit 0
  docker rm -f "$name" >/dev/null 2>&1
  exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "engine.sh: docker not found. Install Docker, then run install.sh in the skill directory." >&2; exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo "engine.sh: docker is installed but the daemon is not running or not accessible." >&2; exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "engine.sh: curl not found. It is needed for the health check." >&2; exit 1
fi

running() { [ -n "$(docker ps -q -f "name=^${name}$")" ]; }

if ! running; then
  # A container left from a crash would block the name. The port is bound to localhost only.
  docker rm -f "$name" >/dev/null 2>&1
  if ! err=$(docker run -d --name "$name" -p "127.0.0.1:$port:$port" ${run_args[@]+"${run_args[@]}"} "$image" 2>&1 >/dev/null); then
    echo "engine.sh: could not start $name: ${err##*$'\n'}" >&2; exit 1
  fi
fi

# Ready when the health endpoint answers. The first start of pocket downloads the model,
# so the wait is generous. A container that exits early fails at once instead.
deadline=$(( $(date +%s) + 300 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  if curl -sf --max-time 2 "$url/health" >/dev/null 2>&1; then
    exit 0
  fi
  if ! running; then
    logs=$(docker logs --tail 3 "$name" 2>&1)
    docker rm -f "$name" >/dev/null 2>&1
    echo "engine.sh: $name stopped on its own. Last log lines: $logs" >&2
    exit 1
  fi
  sleep 1
done
logs=$(docker logs --tail 3 "$name" 2>&1)
docker rm -f "$name" >/dev/null 2>&1
echo "engine.sh: $name did not answer at $url/health within 300 seconds. Last log lines: $logs" >&2
exit 1
