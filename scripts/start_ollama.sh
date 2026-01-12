#!/usr/bin/env bash
# start_ollama.sh
# Start the Ollama Docker container, check GPU VRAM, pull a safe default model,
# and verify container health.

set -euo pipefail

# Default quantized model (safe for RTX 3060)
DEFAULT_MODEL="${OLLAMA_MODEL:-llama3:8b-instruct-q4_K_M}"
MODEL="${1:-$DEFAULT_MODEL}"

CONTAINER_NAME="${OLLAMA_CONTAINER_NAME:-ollama}"

# Detect docker compose command
if command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD="docker-compose"
else
  COMPOSE_CMD="docker compose"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================"
echo "Ollama Docker Startup (Linux)"
echo "========================================"
echo
echo "[INFO] Compose command   : ${COMPOSE_CMD}"
echo "[INFO] Container name    : ${CONTAINER_NAME}"
echo "[INFO] Default model     : ${MODEL}"
echo

# 1. GPU + VRAM check (host)
echo "[*] Checking GPU VRAM via nvidia-smi..."
if command -v nvidia-smi >/dev/null 2>&1; then
  if nvidia_smi_out="$(nvidia-smi 2>&1)"; then
    echo "[OK] nvidia-smi is available."
    echo
    echo "=== nvidia-smi (first 10 lines) ==="
    echo "$nvidia_smi_out" | head -n 10
    echo "==================================="
    echo

    VRAM_TOTAL_MB="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -d ' ')"
    if [[ -n "${VRAM_TOTAL_MB}" && "${VRAM_TOTAL_MB}" =~ ^[0-9]+$ ]]; then
      if (( VRAM_TOTAL_MB < 12000 )); then
        echo "[WARN] VRAM < 12GB (${VRAM_TOTAL_MB} MB)."
        echo "       Unquantized models like 'llama3:latest' will almost certainly cause OOM."
        echo "       This startup script will only allow quantized models (q4/q5/q6/q8)."
      else
        echo "[OK] VRAM is >= 12GB (${VRAM_TOTAL_MB} MB)."
        echo "     Using quantized models is still recommended for stability."
      fi
    else
      echo "[WARN] Could not parse VRAM from nvidia-smi."
    fi
  else
    echo "[WARN] nvidia-smi failed to run; GPU driver might not be configured correctly."
  fi
else
  echo "[WARN] nvidia-smi not found; skipping detailed VRAM checks."
fi

echo
# 2. Start Ollama via Docker Compose
echo "[*] Starting Ollama service using Docker Compose..."
if ! command -v docker >/dev/null 2>&1; then
  echo "[ERROR] Docker is not installed or not in PATH."
  exit 1
fi

if $COMPOSE_CMD up -d ollama; then
  echo "[OK] '${COMPOSE_CMD} up -d ollama' succeeded."
else
  echo "[ERROR] Failed to start Ollama service with '${COMPOSE_CMD} up -d ollama'."
  exit 1
fi

# 3. Wait for health check
echo
echo "[*] Waiting for Ollama container '${CONTAINER_NAME}' to become healthy..."
MAX_WAIT=120
INTERVAL=5
WAITED=0

while (( WAITED < MAX_WAIT )); do
  if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}\$"; then
    echo "[INFO] Container '${CONTAINER_NAME}' not visible yet... waiting."
    sleep "$INTERVAL"
    WAITED=$((WAITED + INTERVAL))
    continue
  fi

  HEALTH="$(docker inspect --format='{{.State.Health.Status}}' "${CONTAINER_NAME}" 2>/dev/null || echo "unknown")"

  if [[ "$HEALTH" == "healthy" ]]; then
    echo "[OK] Container '${CONTAINER_NAME}' is healthy."
    break
  elif [[ "$HEALTH" == "unhealthy" ]]; then
    echo "[ERROR] Container '${CONTAINER_NAME}' is UNHEALTHY."
    echo "  - Check logs: docker logs ${CONTAINER_NAME}"
    exit 1
  else
    echo "[INFO] Health status: ${HEALTH} (waited ${WAITED}/${MAX_WAIT}s)"
    sleep "$INTERVAL"
    WAITED=$((WAITED + INTERVAL))
  fi
done

if (( WAITED >= MAX_WAIT )); then
  echo "[WARN] Container did not report 'healthy' within ${MAX_WAIT}s."
  echo "       It may still be starting. Check logs: docker logs ${CONTAINER_NAME}"
fi

# 4. Ensure at least one quantized model exists; otherwise pull default
echo
echo "[*] Checking installed Ollama models in container '${CONTAINER_NAME}'..."
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}\$"; then
  echo "[ERROR] Container '${CONTAINER_NAME}' is not running after compose up."
  exit 1
fi

if docker exec "${CONTAINER_NAME}" ollama list >/tmp/ollama_models_list 2>&1; then
  echo "[OK] Retrieved model list from Ollama."
  echo
  echo "=== Current models ==="
  cat /tmp/ollama_models_list
  echo "======================"
  echo

  if grep -Eq 'q4|q5|q6|q8' /tmp/ollama_models_list; then
    echo "[OK] At least one quantized model is installed."
  else
    echo "[WARN] No quantized models detected. Pulling default model '${MODEL}'."
    echo
    bash "${SCRIPT_DIR}/pull_ollama_model.sh" "${MODEL}"
  fi
else
  echo "[WARN] Could not list models from Ollama (likely first run)."
  echo "       Pulling default model '${MODEL}'."
  echo
  bash "${SCRIPT_DIR}/pull_ollama_model.sh" "${MODEL}"
fi

# 5. HTTP health check
echo
echo "[*] Performing HTTP health check: http://localhost:11434/api/tags"
if curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
  echo "[OK] Ollama HTTP endpoint is responding."
else
  echo "[WARN] Could not reach Ollama at http://localhost:11434/api/tags."
  echo "       Check logs: docker logs ${CONTAINER_NAME}"
fi

echo
echo "========================================"
echo "Ollama startup complete."
echo "Container : ${CONTAINER_NAME}"
echo "Endpoint  : http://localhost:11434"
echo "Model     : ${MODEL}"
echo "========================================"
