#!/usr/bin/env bash
# pull_ollama_model.sh
# Pull a quantized Ollama model, rejecting unquantized models.

set -euo pipefail

# Priority:
#   1) CLI argument
#   2) OLLAMA_MODEL env
#   3) safe default
MODEL="${1:-${OLLAMA_MODEL:-llama3:8b-instruct-q4_K_M}}"

# If you run Ollama in Docker, set OLLAMA_CONTAINER_NAME (default: ollama)
CONTAINER_NAME="${OLLAMA_CONTAINER_NAME:-ollama}"

echo "========================================"
echo "Ollama Model Pull Script (Linux)"
echo "========================================"
echo
echo "[INFO] Requested model   : ${MODEL}"
echo "[INFO] Target container  : ${CONTAINER_NAME} (if running)"
echo

to_lower() {
  tr '[:upper:]' '[:lower:]'
}

validate_model() {
  local model_name="$1"
  local lower
  lower="$(echo "$model_name" | to_lower)"

  # Absolutely reject clearly unquantized model names
  local disallowed=(
    "llama3:latest"
    "llama3"
    "llama-3"
    "llama-3:latest"
  )

  for dis in "${disallowed[@]}"; do
    if [[ "$lower" == "$dis" ]]; then
      echo "[ERROR] Model '$model_name' is unquantized and NOT allowed."
      echo "        It will almost certainly cause OOM on a 12GB GPU (e.g. RTX 3060)."
      echo "        Use a quantized model like 'llama3:8b-instruct-q4_K_M'."
      return 1
    fi
  done

  # Must contain quantization tag (q4/q5/q6/q8)
  if [[ ! "$model_name" =~ q4|q5|q6|q8 ]]; then
    echo "[ERROR] Model '$model_name' does not contain a quantization tag (q4/q5/q6/q8)."
    echo "        Only quantized models are allowed to protect RTX 3060 VRAM."
    echo "        Recommended: llama3:8b-instruct-q4_K_M"
    return 1
  fi

  return 0
}

echo "[*] Validating model name..."
if ! validate_model "$MODEL"; then
  echo "[ABORT] Model validation failed."
  exit 1
fi

# Decide how to call ollama: Docker vs host
use_docker=false
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}\$"; then
  use_docker=true
  echo "[INFO] Using Ollama inside Docker container '${CONTAINER_NAME}'."
elif command -v ollama >/dev/null 2>&1; then
  echo "[INFO] Using local 'ollama' CLI on host."
else
  echo "[ERROR] No Ollama container '${CONTAINER_NAME}' and no local 'ollama' CLI found."
  echo "  - Start the container: docker compose up -d ollama"
  echo "  - Or install Ollama natively: https://github.com/ollama/ollama"
  exit 1
fi

echo
echo "[*] Pulling model '${MODEL}'..."
echo "    This may take several minutes depending on your internet speed."
echo

if [[ "$use_docker" == "true" ]]; then
  if docker exec "$CONTAINER_NAME" ollama pull "$MODEL"; then
    echo
    echo "[OK] Model '${MODEL}' pulled successfully into container '${CONTAINER_NAME}'."
    echo
    echo "[*] Installed models in container:"
    docker exec "$CONTAINER_NAME" ollama list || true
  else
    echo
    echo "[ERROR] Failed to pull model '${MODEL}' in container '${CONTAINER_NAME}'."
    exit 1
  fi
else
  if ollama pull "$MODEL"; then
    echo
    echo "[OK] Model '${MODEL}' pulled successfully on host."
    echo
    echo "[*] Installed models on host:"
    ollama list || true
  else
    echo
    echo "[ERROR] Failed to pull model '${MODEL}' on host."
    exit 1
  fi
fi

echo
echo "========================================"
echo "Model pull complete."
echo "========================================"
