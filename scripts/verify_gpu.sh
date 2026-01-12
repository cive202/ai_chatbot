#!/bin/bash
# Bash script to verify GPU access in Docker
# Tests NVIDIA runtime availability and displays GPU information

echo "========================================"
echo "GPU Verification for Docker"
echo "========================================"
echo ""

# Check Docker installation
echo "Step 1: Checking Docker installation..."
if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker is not installed or not in PATH"
    exit 1
fi
echo "Docker found: $(docker --version)"

# Check Docker Compose
echo ""
echo "Step 2: Checking Docker Compose..."
if command -v docker-compose &> /dev/null; then
    echo "docker-compose found: $(docker-compose --version)"
    COMPOSE_CMD="docker-compose"
elif docker compose version &> /dev/null; then
    echo "Docker Compose found: $(docker compose version)"
    COMPOSE_CMD="docker compose"
else
    echo "ERROR: Docker Compose is not installed"
    exit 1
fi

# Test GPU access
echo ""
echo "Step 3: Testing GPU access in Docker..."
echo "Running: docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi"
echo ""

if docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi; then
    echo ""
    echo "SUCCESS: GPU access verified!"
    
    # Extract GPU info
    echo ""
    echo "GPU Information:"
    docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
    
    # Check VRAM
    echo ""
    VRAM_MB=$(docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | tr -d ' ')
    VRAM_GB=$((VRAM_MB / 1024))
    
    if [ "$VRAM_GB" -lt 12 ]; then
        echo "WARNING: GPU has ${VRAM_GB}GB VRAM (< 12GB)"
        echo "CRITICAL: You MUST use quantized models (Q4 or Q5)!"
        echo "DO NOT use 'llama3:latest' - it will cause OOM errors!"
        echo "Recommended: llama3:8b-instruct-q4_K_M (~4.5GB)"
    else
        echo "GPU has ${VRAM_GB}GB VRAM"
        echo "Still recommended to use quantized models for better performance"
    fi
else
    echo ""
    echo "ERROR: GPU access test failed!"
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Ensure NVIDIA drivers are installed (latest version)"
    echo "2. Install NVIDIA Container Toolkit:"
    echo "   https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html"
    echo "3. Restart Docker daemon: sudo systemctl restart docker"
    exit 1
fi

echo ""
echo "========================================"
echo "Verification Complete!"
echo "========================================"
