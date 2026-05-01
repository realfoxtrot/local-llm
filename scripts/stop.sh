#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

log_info "Stopping Local LLM Server..."

docker compose down --remove-orphans 2>/dev/null || true
docker compose -f docker-compose.pp.yml down --remove-orphans 2>/dev/null || true

# Optional: clear unused containers/images
read -r -p "Remove unused Docker images to free disk space? [y/N] " response || true
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    docker system prune -f
    log_info "Unused images removed"
fi

log_info "Server stopped"
