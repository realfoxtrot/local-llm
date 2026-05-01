# Local LLM Server

Production-ready Docker stack for serving state-of-the-art open-weight LLMs with an OpenAI-compatible API endpoint on local hardware. Optimized for **2x NVIDIA RTX 3090 (24GB)** on **Ubuntu 24.04**.

## Hardware Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| GPU | 1x NVIDIA GPU (Ampere+) | **2x RTX 3090 24GB** |
| System RAM | 32 GB | **64 GB+** |
| Storage | 100 GB SSD | **200 GB+ NVMe** |
| Network | Gigabit Ethernet | **10GbE for multi-user** |
| OS | Ubuntu 22.04+ | **Ubuntu 24.04 LTS** |

> **Why 2x RTX 3090?** Two RTX 3090s provide 48GB of VRAM, which fits a **70B parameter model at 4-bit quantization** (e.g., Llama 3.3 70B W4A16) with sufficient KV cache headroom for concurrent requests. This delivers near-GPT-4 quality completely offline.

## Quick Start

```bash
# 1. Clone this repository to your server
git clone https://github.com/yourusername/local-llm-server.git
cd local-llm-server

# 2. Run the automated setup (installs Docker, NVIDIA Container Toolkit, tunes OS)
sudo ./scripts/setup.sh

# 3. Edit environment configuration
nano .env
# Set HF_TOKEN=your_huggingface_token
# Set VLLM_API_KEY=your_secure_api_key

# 4. Start the server (Tensor Parallelism mode)
./scripts/start.sh

# 5. Test the API
./scripts/test.sh
```

The API is now available at:
- **Direct**: `http://your-server-ip:8000/v1/chat/completions`
- **Via Nginx**: `http://your-server-ip/v1/chat/completions`

## Default Model

**[RedHatAI/Llama-3.3-70B-Instruct-quantized.w4a16](https://huggingface.co/RedHatAI/Llama-3.3-70B-Instruct-quantized.w4a16)**

- **Architecture**: Llama 3.3 70B Instruct
- **Quantization**: W4A16 (INT4 weights, INT16 activations) via Neural Magic
- **VRAM Usage**: ~40GB across 2 GPUs
- **Quality**: Minimal degradation vs FP16; beats many closed APIs on benchmarks
- **Context**: Up to 128K tokens (configurable, default 32K)
- **License**: Llama 3 Community License (free for commercial use)

## Repository Structure

```
local-llm-server/
├── docker-compose.yml              # Main stack (Tensor Parallelism)
├── docker-compose.pp.yml           # Alternative (Pipeline Parallelism)
├── .env.example                    # Configuration template
├── README.md                       # This file
├── scripts/
│   ├── setup.sh                    # One-time Ubuntu server setup
│   ├── start.sh                    # Start the stack
│   ├── stop.sh                     # Stop the stack
│   ├── logs.sh                     # View container logs
│   ├── test.sh                     # API health & functionality tests
│   ├── benchmark.sh                # Simple load test
│   └── update-model.sh             # Switch to a different model
├── nginx/
│   └── nginx.conf                  # Reverse proxy config
├── examples/
│   ├── openai_client.py            # Python client example
│   └── openai_client.js            # Node.js client example
├── configs/
│   └── vllm-2x3090.yaml            # Tuned vLLM parameters
├── monitoring/                     # Optional Prometheus + Grafana
└── models/                           # Local model cache mount
```

## Parallelism Modes

For dual RTX 3090s connected via **PCIe** (no NVLink), you have two deployment strategies:

### Tensor Parallelism (TP) - Default

**File**: `docker-compose.yml` | **Command**: `./scripts/start.sh`

- Splits each layer's weight matrices across both GPUs
- All GPUs process every request simultaneously
- **Best for**: Lower latency per request, simpler reasoning
- **Trade-off**: All-reduce communication after every layer adds overhead on PCIe

### Pipeline Parallelism (PP) - Higher Throughput

**File**: `docker-compose.pp.yml` | **Command**: `./scripts/start.sh pp`

- Splits model layers across GPUs (GPU 0: layers 0-39, GPU 1: layers 40-79)
- Fills pipeline "bubbles" with concurrent requests from other users
- **Best for**: Higher throughput with multiple concurrent clients on PCIe GPUs
- **Trade-off**: Slightly higher latency for single-user scenarios

> **Recommendation**: Start with **TP mode** for personal/low-concurrency use. Switch to **PP mode** if you are serving multiple users simultaneously from your local network.

## Configuration Reference

Edit `.env` to tune performance:

| Variable | Default | Description |
|----------|---------|-------------|
| `VLLM_MODEL` | `RedHatAI/Llama-3.3-70B-Instruct-quantized.w4a16` | HuggingFace model ID |
| `HF_TOKEN` | *(required)* | HuggingFace token for gated models |
| `VLLM_API_KEY` | `change-me` | API key for endpoint authentication |
| `TENSOR_PARALLEL_SIZE` | `2` | GPUs for tensor parallelism |
| `PIPELINE_PARALLEL_SIZE` | `1` | GPUs for pipeline parallelism |
| `GPU_MEMORY_UTILIZATION` | `0.92` | Fraction of VRAM to use (0.90-0.95) |
| `MAX_MODEL_LEN` | `32768` | Maximum context length in tokens |
| `MAX_NUM_SEQS` | `128` | Max concurrent sequences (throughput vs latency) |
| `MAX_NUM_BATCHED_TOKENS` | `8192` | Tokens per batch |
| `ENABLE_PREFIX_CACHING` | `true` | Reuse KV cache for repeated prompts |
| `VLLM_PORT` | `8000` | API server port |
| `NGINX_HTTP_PORT` | `80` | Reverse proxy port |
| `SERVER_HOSTNAME` | `llm.local` | Local hostname for Nginx |

## API Usage

Any OpenAI-compatible client works without modification.

### Python

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://your-server-ip:8000/v1",
    api_key="your-vllm-api-key",  # from .env
)

response = client.chat.completions.create(
    model="llama-3.3-70b",
    messages=[{"role": "user", "content": "Hello!"}],
    stream=True,
)

for chunk in response:
    print(chunk.choices[0].delta.content or "", end="")
```

### cURL

```bash
curl http://your-server-ip:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your-vllm-api-key" \
  -d '{
    "model": "llama-3.3-70b",
    "messages": [{"role": "user", "content": "Hello!"}],
    "stream": true
  }'
```

### LangChain / LlamaIndex

```python
from langchain_openai import ChatOpenAI

llm = ChatOpenAI(
    model="llama-3.3-70b",
    openai_api_key="your-vllm-api-key",
    openai_api_base="http://your-server-ip:8000/v1",
    temperature=0.7,
)
```

## Model Recommendations for 2x RTX 3090

| Model | Size | Quantization | Quality | Use Case |
|-------|------|--------------|---------|----------|
| **Llama 3.3 70B W4A16** | 40GB | W4A16 | Excellent | General purpose, coding, reasoning |
| **Llama 3.1 70B W4A16** | 40GB | W4A16 | Excellent | Alternative to 3.3 |
| **Qwen2.5 72B W4A16** | 40GB | W4A16 | Excellent | Multilingual, long context |
| **Mixtral 8x7B W4A16** | 45GB | W4A16 | Very Good | MoE architecture, fast inference |

Switch models with:
```bash
./scripts/update-model.sh RedHatAI/Qwen2-72B-Instruct-quantized.w4a16 qwen2-72b
./scripts/stop.sh
./scripts/start.sh
```

## Performance Tuning

### Maximizing Throughput (Many Users)

```env
GPU_MEMORY_UTILIZATION=0.95
MAX_NUM_SEQS=256
MAX_NUM_BATCHED_TOKENS=16384
ENABLE_PREFIX_CACHING=true
```
Use Pipeline Parallelism: `./scripts/start.sh pp`

### Minimizing Latency (Single User)

```env
GPU_MEMORY_UTILIZATION=0.90
MAX_NUM_SEQS=16
MAX_NUM_BATCHED_TOKENS=4096
MAX_MODEL_LEN=8192
```
Use Tensor Parallelism: `./scripts/start.sh`

### Context Length vs. Concurrency Trade-off

With 2x RTX 3090 and 70B W4A16, you have ~8GB total KV cache headroom. This means:

| Context Length | Estimated Max Concurrent Requests |
|---------------|----------------------------------|
| 4K tokens | ~32 |
| 8K tokens | ~16 |
| 16K tokens | ~8 |
| 32K tokens | ~4 |

Reduce `MAX_MODEL_LEN` if you don't need long contexts to fit more concurrent users.

## Monitoring (Optional)

Enable Prometheus + Grafana:

```bash
export ENABLE_MONITORING=true
docker compose -f docker-compose.yml -f docker-compose.monitor.yml up -d
```

Access Grafana at `http://your-server-ip:3000` (admin/admin).

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| `CUDA out of memory` | Model too large / concurrency too high | Lower `MAX_NUM_SEQS` or `MAX_MODEL_LEN`; ensure W4A16 model |
| `NCCL error` | Multi-GPU communication failure | Add `--disable-custom-all-reduce`; verify PCIe lanes |
| `401 Unauthorized` | HF_TOKEN missing / invalid | Set token in `.env`; accept model license on HuggingFace |
| `Slow first startup` | Model downloading | Normal; 40GB+ download; persists in Docker volume |
| `Connection refused` | Server not ready | Wait 2-5 minutes for model loading; check `docker logs` |
| `GPU not detected` | NVIDIA Container Toolkit issue | Run `sudo ./scripts/setup.sh` to reinstall |

## Security Notes

- **Change the default `VLLM_API_KEY`** in `.env` before exposing to your network
- The stack binds to `0.0.0.0` by default, making it available on your local network
- Nginx adds CORS headers for browser-based clients
- For internet exposure, add HTTPS/SSL (certbot or reverse proxy)
- Consider firewall rules (`ufw`) to restrict port 8000/80 to your LAN subnet

## Benchmarks (Expected)

On **2x RTX 3090** with **Llama 3.3 70B W4A16**:

| Metric | Tensor Parallelism | Pipeline Parallelism |
|--------|-------------------|---------------------|
| Time to First Token (1 user) | ~0.3s | ~0.5s |
| Tokens/sec (1 user) | ~25-35 tok/s | ~20-30 tok/s |
| Tokens/sec (10 concurrent) | ~60-80 tok/s | ~90-120 tok/s |
| Requests/sec (10 concurrent) | ~4-6 req/s | ~8-12 req/s |

> Actual numbers vary with prompt length, temperature, and system configuration.

## Advanced: Custom Models

To use a local model checkpoint instead of HuggingFace:

1. Place the model directory in `./models/my-model/`
2. Update `.env`:
   ```env
   VLLM_MODEL=/models/my-model
   ```
3. Ensure the model is in HuggingFace format (not GGUF) with `config.json`

## License

This repository configuration is provided as-is under the MIT License.

**Model License**: The default Llama 3.3 70B model is subject to the [Llama 3 Community License](https://github.com/meta-llama/llama-models/blob/main/models/llama3_3/LICENSE).

## Acknowledgments

- [vLLM](https://github.com/vllm-project/vllm) - PagedAttention and continuous batching
- [Neural Magic](https://neuralmagic.com/) - W4A16 quantization
- [Meta AI](https://ai.meta.com/) - Llama model family
