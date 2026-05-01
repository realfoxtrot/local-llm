#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }

# Usage: ./scripts/update-model.sh <huggingface-model-id> [served-name]
MODEL_ID="${1:-}"
SERVED_NAME="${2:-custom-model}"

if [[ -z "$MODEL_ID" ]]; then
    echo "Usage: $0 <huggingface-model-id> [served-model-name]"
    echo ""
    echo "Examples:"
    echo "  $0 RedHatAI/Llama-3.3-70B-Instruct-quantized.w4a16 llama-3.3-70b"
    echo "  $0 RedHatAI/Meta-Llama-3.1-70B-Instruct-quantized.w4a16 llama-3.1-70b"
    echo "  $0 RedHatAI/Qwen2-72B-Instruct-quantized.w4a16 qwen2-72b"
    echo ""
    echo "Tips for 2x RTX 3090 (48GB total):"
    echo "  - Use W4A16 quantized models (~40GB weights, leaves room for KV cache)"
    echo "  - LLaMA 70B, Qwen 72B, Mixtral 8x7B fit well at 4-bit"
    echo "  - Avoid unquantized FP16 70B models (need ~140GB)"
    exit 1
fi

log_warn "This will update .env to use model: $MODEL_ID"
read -r -p "Continue? [y/N] " response || true
if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    log_info "Aborted"
    exit 0
fi

# Update .env
if grep -q "^VLLM_MODEL=" .env 2>/dev/null; then
    sed -i "s|^VLLM_MODEL=.*|VLLM_MODEL=$MODEL_ID|" .env
else
    echo "VLLM_MODEL=$MODEL_ID" >> .env
fi

if grep -q "^SERVED_MODEL_NAME=" .env 2>/dev/null; then
    sed -i "s|^SERVED_MODEL_NAME=.*|SERVED_MODEL_NAME=$SERVED_NAME|" .env
else
    echo "SERVED_MODEL_NAME=$SERVED_NAME" >> .env
fi

log_info "Updated .env:"
grep -E "^(VLLM_MODEL|SERVED_MODEL_NAME)=" .env

echo ""
log_warn "Stop and restart the server to load the new model:"
echo "  ./scripts/stop.sh"
echo "  ./scripts/start.sh"
