#!/usr/bin/env bash
set -euo pipefail

echo "Local LLM Server Logs"
echo "====================="
echo ""

if [[ "${1:-}" == "pp" || "${1:-}" == "pipeline" ]]; then
    COMPOSE_FILE="docker-compose.pp.yml"
else
    COMPOSE_FILE="docker-compose.yml"
fi

docker compose -f "$COMPOSE_FILE" logs -f
