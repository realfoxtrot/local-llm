#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Local LLM Server Setup Script for Ubuntu 24.04
# Hardware: 2x NVIDIA RTX 3090 (24GB each), 64GB+ RAM
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC}  $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi
}

check_gpu() {
    log_step "Checking NVIDIA GPUs..."
    if ! command -v nvidia-smi &> /dev/null; then
        log_error "nvidia-smi not found. Please install NVIDIA drivers first."
        log_info "Visit: https://www.nvidia.com/Download/index.aspx"
        exit 1
    fi

    echo ""
    nvidia-smi --query-gpu=name,driver_version,memory.total,pci.bus_id --format=csv,noheader
    echo ""

    GPU_COUNT=$(nvidia-smi -L | wc -l)
    log_info "Detected $GPU_COUNT NVIDIA GPU(s)"

    if [[ "$GPU_COUNT" -lt 2 ]]; then
        log_warn "Expected 2 GPUs for optimal performance. Continuing with $GPU_COUNT GPU(s)."
    fi
}

install_docker() {
    log_step "Installing Docker Engine..."
    if command -v docker &> /dev/null; then
        log_info "Docker already installed: $(docker --version)"
        return 0
    fi

    apt-get update
    apt-get install -y ca-certificates curl gnupg lsb-release

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    log_info "Docker installed successfully"
}

install_nvidia_container_toolkit() {
    log_step "Installing NVIDIA Container Toolkit..."

    if command -v nvidia-ctk &> /dev/null; then
        log_info "nvidia-ctk already installed: $(nvidia-ctk --version 2>/dev/null || echo 'version unknown')"
        return 0
    fi

    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

    apt-get update
    apt-get install -y nvidia-container-toolkit

    nvidia-ctk runtime configure --runtime=docker
    systemctl restart docker

    log_info "NVIDIA Container Toolkit installed and Docker runtime configured"
}

verify_docker_gpu() {
    log_step "Verifying Docker GPU access..."
    if ! docker run --rm --runtime=nvidia --gpus all nvidia/cuda:12.6.2-base-ubuntu22.04 nvidia-smi > /dev/null 2>&1; then
        log_error "Docker GPU test failed. Trying with --gpus all..."
        docker run --rm --gpus all nvidia/cuda:12.6.2-base-ubuntu22.04 nvidia-smi || {
            log_error "Cannot run GPU containers. Check NVIDIA Container Toolkit installation."
            exit 1
        }
    fi
    log_info "Docker GPU access verified"
}

configure_system() {
    log_step "Tuning system for LLM inference..."

    # Increase shared memory limits
    cat > /etc/sysctl.d/99-llm-server.conf << 'EOF'
# Kernel settings for LLM inference
kernel.shmmax = 68719476736
kernel.shmall = 4294967296
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
EOF

    sysctl --system

    # Increase file descriptor limits
    cat > /etc/security/limits.d/99-llm-server.conf << 'EOF'
* soft nofile 65535
* hard nofile 65535
* soft memlock unlimited
* hard memlock unlimited
EOF

    # Disable NUMA balancing for consistent GPU memory allocation
    if [[ -f /proc/sys/kernel/numa_balancing ]]; then
        echo 0 > /proc/sys/kernel/numa_balancing || true
    fi

    log_info "System tuning applied"
}

pull_images() {
    log_step "Pulling Docker images..."
    docker pull vllm/vllm-openai:latest
    docker pull nginx:alpine
    log_info "Images pulled"
}

create_env() {
    log_step "Creating environment configuration..."
    if [[ ! -f .env ]]; then
        cp .env.example .env
        log_warn "Created .env from .env.example. Please edit it and set your HF_TOKEN and VLLM_API_KEY!"
    else
        log_info ".env already exists, skipping"
    fi
}

main() {
    echo ""
    echo "=========================================="
    echo "  Local LLM Server - Ubuntu 24.04 Setup"
    echo "  Target: 2x RTX 3090 + vLLM stack"
    echo "=========================================="
    echo ""

    check_root
    check_gpu
    install_docker
    install_nvidia_container_toolkit
    verify_docker_gpu
    configure_system
    pull_images
    create_env

    echo ""
    log_info "Setup complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Edit .env and set your HuggingFace token (HF_TOKEN)"
    echo "     Get one at: https://huggingface.co/settings/tokens"
    echo "  2. Start the server:    ./scripts/start.sh"
    echo "  3. Test the API:        ./scripts/test.sh"
    echo "  4. Benchmark:           ./scripts/benchmark.sh"
    echo ""
    echo "API endpoint will be available at:"
    echo "  - Direct:    http://localhost:8000/v1/chat/completions"
    echo "  - Via Nginx: http://localhost/v1/chat/completions"
    echo ""
}

main "$@"
