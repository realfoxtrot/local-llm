#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC}  $1"; }

COMPOSE_FILE="${1:-docker-compose.yml}"
MODE="${2:-}"

if [[ "$COMPOSE_FILE" == "pp" || "$COMPOSE_FILE" == "pipeline" ]]; then
    COMPOSE_FILE="docker-compose.pp.yml"
    log_info "Using Pipeline Parallelism mode (optimized for PCIe-connected GPUs)"
fi

if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo "Usage: $0 [docker-compose.yml|pp|pipeline] [detached]"
    echo ""
    echo "Modes:"
    echo "  (default)      Tensor Parallelism (TP=2) - lower latency"
    echo "  pp/pipeline    Pipeline Parallelism (PP=2) - higher throughput on PCIe"
    exit 1
fi

log_step "Starting Local LLM Server with $COMPOSE_FILE"

if [[ ! -f .env ]]; then
    log_warn ".env not found. Copying from .env.example..."
    cp .env.example .env
    log_warn "Please edit .env and set HF_TOKEN before the first run!"
fi

# Ensure model cache directories exist
mkdir -p models

# Check GPU availability
if ! nvidia-smi > /dev/null 2>&1; then
    echo "ERROR: nvidia-smi failed. NVIDIA drivers not installed?"
    exit 1
fi

GPU_COUNT=$(nvidia-smi -L 2>/dev/null | wc -l)
log_info "Detected $GPU_COUNT GPU(s)"

if [[ "$GPU_COUNT" -lt 2 ]]; then
    log_warn "Only $GPU_COUNT GPU detected. Multi-GPU configs may fail."
fi

# Docker Compose up
if [[ "$MODE" == "detached" || "$MODE" == "-d" ]]; then
    docker compose -f "$COMPOSE_FILE" up -d
    log_info "Server started in detached mode"
    log_info "View logs: docker compose -f $COMPOSE_FILE logs -f"
else
    log_info "Starting in attached mode (Ctrl+C to stop)..."
    docker compose -f "$COMPOSE_FILE" up
fi
