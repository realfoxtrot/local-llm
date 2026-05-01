#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC}  $1"; }

# Load config from .env
if [[ -f .env ]]; then
    export $(grep -v '^#' .env | xargs) 2>/dev/null || true
fi

BASE_URL="${1:-http://localhost:8000}"
MODEL_NAME="${SERVED_MODEL_NAME:-llama-3.3-70b}"
API_KEY="${VLLM_API_KEY:-change-me}"

DURATION="${2:-60}"
CONCURRENCY="${3:-10}"

log_step "Benchmarking LLM Server"
echo "Endpoint:     $BASE_URL"
echo "Model:        $MODEL_NAME"
echo "Duration:     ${DURATION}s"
echo "Concurrency:  $CONCURRENCY"
echo ""

# Check if hey (HTTP load generator) is available
if command -v hey &> /dev/null; then
    LOAD_GEN="hey"
# Check if apache2-utils (ab) is available
elif command -v ab &> /dev/null; then
    LOAD_GEN="ab"
else
    log_warn "No load generator found. Installing hey..."
    curl -fsSL -o /tmp/hey.tar.gz https://github.com/rakyll/hey/releases/download/v0.1.4/hey_0.1.4_linux_amd64.tar.gz || {
        log_warn "Could not install hey. Using simple curl-based benchmark."
        LOAD_GEN="curl"
    }
    if [[ "$LOAD_GEN" != "curl" ]]; then
        tar -xzf /tmp/hey.tar.gz -C /tmp hey 2>/dev/null || true
        chmod +x /tmp/hey 2>/dev/null || true
        mv /tmp/hey /usr/local/bin/hey 2>/dev/null || true
        LOAD_GEN="hey"
    fi
fi

# Prepare benchmark payload
PAYLOAD='{
    "model": "'"$MODEL_NAME"'",
    "messages": [
        {"role": "system", "content": "You are a helpful assistant. Answer concisely."},
        {"role": "user", "content": "Explain quantum computing in 3 sentences."}
    ],
    "max_tokens": 256,
    "temperature": 0.7
}'

if [[ "$LOAD_GEN" == "hey" ]]; then
    log_info "Running benchmark with hey..."
    hey -z "${DURATION}s" -c "$CONCURRENCY" -m POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $API_KEY" \
        -d "$PAYLOAD" \
        "$BASE_URL/v1/chat/completions"
elif [[ "$LOAD_GEN" == "ab" ]]; then
    log_warn "ab does not support concurrent POST payload well. Using simple test."
    echo "$PAYLOAD" > /tmp/benchmark_payload.json
    ab -n 10 -c 2 -T "application/json" -H "Authorization: Bearer $API_KEY" \
        -p /tmp/benchmark_payload.json "$BASE_URL/v1/chat/completions"
else
    log_info "Running simple sequential benchmark..."
    TOTAL_TIME=0
    REQUESTS=0
    for i in {1..10}; do
        START=$(date +%s%N)
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $API_KEY" \
            -d "$PAYLOAD" \
            "$BASE_URL/v1/chat/completions")
        END=$(date +%s%N)
        TIME=$(( (END - START) / 1000000 ))
        if [[ "$HTTP_CODE" == "200" ]]; then
            TOTAL_TIME=$((TOTAL_TIME + TIME))
            REQUESTS=$((REQUESTS + 1))
            echo "Request $i: ${TIME}ms"
        else
            echo "Request $i: FAILED (HTTP $HTTP_CODE)"
        fi
    done
    if [[ $REQUESTS -gt 0 ]]; then
        AVG=$((TOTAL_TIME / REQUESTS))
        echo ""
        log_info "Average latency: ${AVG}ms over $REQUESTS requests"
    fi
fi

echo ""
log_info "Benchmark complete. Check GPU utilization during runs with: watch -n 1 nvidia-smi"
