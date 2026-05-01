#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Load API key from .env if available
API_KEY="${VLLM_API_KEY:-change-me}"
if [[ -f .env ]]; then
    # shellcheck source=/dev/null
    export $(grep -v '^#' .env | xargs) 2>/dev/null || true
    API_KEY="${VLLM_API_KEY:-$API_KEY}"
fi

BASE_URL="${1:-http://localhost:8000}"
MODEL_NAME="${SERVED_MODEL_NAME:-llama-3.3-70b}"

echo ""
echo "========================================"
echo "  Local LLM Server - API Test"
echo "========================================"
echo ""
echo "Endpoint: $BASE_URL"
echo "Model:    $MODEL_NAME"
echo ""

# Test 1: Health check
log_info "Test 1: Health endpoint"
if curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/health" | grep -q "200"; then
    log_info "Health check: PASSED"
else
    log_error "Health check: FAILED (server may still be loading the model)"
    log_info "Large models can take 2-5 minutes to load. Retry shortly."
fi

echo ""

# Test 2: List models (OpenAI compatible)
log_info "Test 2: List available models"
MODELS_RESPONSE=$(curl -s "$BASE_URL/v1/models" -H "Authorization: Bearer $API_KEY" || true)
if echo "$MODELS_RESPONSE" | grep -q "$MODEL_NAME"; then
    log_info "Model listing: PASSED"
    echo "$MODELS_RESPONSE" | head -c 200
    echo ""
else
    log_warn "Model listing: Got unexpected response"
    echo "$MODELS_RESPONSE" | head -c 200
    echo ""
fi

echo ""

# Test 3: Simple chat completion
log_info "Test 3: Chat completion (non-streaming)"
COMPLETION_RESPONSE=$(curl -s "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d "{
        \"model\": \"$MODEL_NAME\",
        \"messages\": [{\"role\": \"user\", \"content\": \"Say exactly the following: 'The LLM server is running and responding correctly.'\"}],
        \"max_tokens\": 50,
        \"temperature\": 0.0
    }" || true)

if echo "$COMPLETION_RESPONSE" | grep -q "running"; then
    log_info "Chat completion: PASSED"
else
    log_warn "Chat completion: Check response below"
fi

echo ""
echo "Response:"
echo "$COMPLETION_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$COMPLETION_RESPONSE"

echo ""

# Test 4: Streaming chat completion
log_info "Test 4: Streaming chat completion"
echo -n "Response: "
curl -s "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d "{
        \"model\": \"$MODEL_NAME\",
        \"messages\": [{\"role\": \"user\", \"content\": \"Count from 1 to 5\"}],
        \"max_tokens\": 30,
        \"temperature\": 0.0,
        \"stream\": true
    }" | while read -r line; do
    if [[ "$line" == data:* ]]; then
        content=$(echo "$line" | sed 's/^data: //' | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('choices',[{}])[0].get('delta',{}).get('content',''), end='')" 2>/dev/null || true)
        echo -n "$content"
    fi
done

echo ""
echo ""
log_info "All tests completed"
