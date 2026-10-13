#!/usr/bin/env bash
# Helper for the generic Docker setup. Run from your repository root:
#
#   ./DockerFile/run.sh build    build the four images ONE AT A TIME (stops at the first failure)
#   ./DockerFile/run.sh up       start everything with the images that exist
#   ./DockerFile/run.sh clean    stop, DELETE ALL unused images, build fresh, start
#   ./DockerFile/run.sh status   what runs, and is it healthy
#   ./DockerFile/run.sh logs [service]
#   ./DockerFile/run.sh down     stop everything (data is kept)
#
# `clean` runs `docker image prune -af`: it deletes EVERY image on this machine
# that no running container uses, also images of other projects. Add -y to skip
# the question:  ./DockerFile/run.sh clean -y
set -euo pipefail

[ -f docker-compose.yml ] || { echo "Run this from your repository root (docker-compose.yml not found)." >&2; exit 1; }
[ -f .env ] || { echo ".env not found in $(pwd). Create it first (see DockerFile/README.md)." >&2; exit 1; }

SERVICES="auth-service order-service executor-service frontend"
enabled() { docker compose config --services 2>/dev/null | grep -qx "$1"; }

case "${1:-}" in
  build)
    for s in $SERVICES; do
      enabled "$s" || { echo "== $s: not in COMPOSE_PROFILES, skipped"; continue; }
      echo "== building $s"
      docker compose build "$s" || { echo "BUILD FAILED: $s  (fix it, then run again)" >&2; exit 1; }
    done
    docker images | grep -E "^(frontend|auth-service|order-service|executor-service) " || true
    ;;
  up)
    docker compose up -d
    docker compose ps
    ;;
  clean)
    if [ "${2:-}" != "-y" ]; then
      read -r -p "This deletes ALL unused Docker images on this machine. Continue? [y/N] " a
      [ "$a" = y ] || [ "$a" = Y ] || { echo "Cancelled."; exit 0; }
    fi
    docker compose down
    docker image prune -af
    docker compose up --build -d
    docker compose ps
    ;;
  status) docker compose ps ;;
  logs)   shift; docker compose logs --tail 100 -f "$@" ;;
  down)   docker compose down ;;
  *) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
