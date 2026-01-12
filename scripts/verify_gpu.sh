#!/usr/bin/env bash
# verify_gpu.sh
# Verify NVIDIA GPU presence, VRAM, and Docker GPU access on Linux.

set -euo pipefail

CUDA_TEST_IMAGE="nvidia/cuda:11.8.0-base-ubuntu22.04"

echo "========================================"
echo "GPU Verification for Linux + Docker"
echo "========================================"
echo

# 1. Check nvidia-smi availability
echo "[*] Checking for nvidia-smi..."
if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo "[ERROR] nvidia-smi not found."
  echo "  - Install NVIDIA drivers and CUDA toolkit for your GPU."
  echo "  - On Ubuntu, for example: sudo apt install nvidia-driver-535 (or appropriate driver)."
  exit 1
fi

# 2. Query GPU info
echo "[*] Querying GPU information via nvidia-smi..."
if ! nvidia_smi_out="$(nvidia-smi 2>&1)"; then
  echo "[ERROR] nvidia-smi failed to run:"
  echo "$nvidia_smi_out"
  exit 1
fi

echo
echo "=== nvidia-smi (first 12 lines) ==="
echo "$nvidia_smi_out" | head -n 12
echo "==================================="
echo

GPU_NAME="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1 | sed 's/^[[:space:]]*//')"
VRAM_TOTAL_MB="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -d ' ')"
VRAM_FREE_MB="$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -d ' ')"
DRIVER_VERSION="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1 | sed 's/^[[:space:]]*//')"

echo "[INFO] GPU Name        : ${GPU_NAME:-unknown}"
echo "[INFO] Driver Version  : ${DRIVER_VERSION:-unknown}"

if [[ -n "${VRAM_TOTAL_MB}" && "${VRAM_TOTAL_MB}" =~ ^[0-9]+$ ]]; then
  echo "[INFO] VRAM Total      : ${VRAM_TOTAL_MB} MB"
else
  echo "[WARN] Could not determine total VRAM."
fi

if [[ -n "${VRAM_FREE_MB}" && "${VRAM_FREE_MB}" =~ ^[0-9]+$ ]]; then
  echo "[INFO] VRAM Free       : ${VRAM_FREE_MB} MB"
else
  echo "[WARN] Could not determine free VRAM."
fi

# 3. VRAM warnings, especially for unquantized models
if [[ -n "${VRAM_TOTAL_MB}" && "${VRAM_TOTAL_MB}" =~ ^[0-9]+$ ]]; then
  if (( VRAM_TOTAL_MB < 12000 )); then
    echo
    echo "[WARN] Detected VRAM < 12GB (${VRAM_TOTAL_MB} MB)."
    echo "       Unquantized Llama-3 8B (e.g. 'llama3:latest') will most likely cause OOM and crash."
    echo "       You MUST use quantized models (q4/q5) such as:"
    echo "       - llama3:8b-instruct-q4_K_M  (~4.5GB)"
    echo "       - llama3:8b-instruct-q5_K_M  (~5.5GB)"
  else
    echo
    echo "[OK] VRAM is >= 12GB (${VRAM_TOTAL_MB} MB)."
    echo "     Still recommended to use quantized models for stability and concurrency."
  fi
fi

# 4. Test Docker + NVIDIA GPU
echo
echo "[*] Testing Docker GPU access with image: ${CUDA_TEST_IMAGE}"
if ! command -v docker >/dev/null 2>&1; then
  echo "[ERROR] Docker is not installed or not in PATH."
  echo "  - Install Docker and ensure your user is in the 'docker' group."
  exit 1
fi

# Pull image if needed
if ! docker image inspect "${CUDA_TEST_IMAGE}" >/dev/null 2>&1; then
  echo "[*] Pulling CUDA test image (this may take a while): ${CUDA_TEST_IMAGE}"
  docker pull "${CUDA_TEST_IMAGE}"
fi

echo
echo "[*] Running nvidia-smi inside Docker..."
if docker run --rm --gpus all "${CUDA_TEST_IMAGE}" nvidia-smi >/tmp/docker_nvidia_smi 2>&1; then
  echo "[OK] Docker can access the GPU."
  echo
  echo "=== nvidia-smi inside Docker (first 10 lines) ==="
  head -n 10 /tmp/docker_nvidia_smi || true
  echo "================================================"
else
  echo "[ERROR] Docker could NOT access the GPU."
  echo "Output from container:"
  cat /tmp/docker_nvidia_smi || true
  echo
  echo "Troubleshooting:"
  echo "  - Install NVIDIA Container Toolkit:"
  echo "    https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html"
  echo "  - Ensure Docker daemon uses NVIDIA runtime."
  echo "  - Restart Docker: sudo systemctl restart docker"
  exit 1
fi

echo
echo "========================================"
echo "GPU + Docker verification complete."
echo "========================================"
