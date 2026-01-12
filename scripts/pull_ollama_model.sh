#!/bin/bash
# Bash script to pull quantized Ollama model into container
# CRITICAL: This script validates model names to prevent pulling unquantized models

MODEL="${1:-llama3:8b-instruct-q4_K_M}"
CONTAINER_NAME="${2:-ollama}"

# Function to validate model name
validate_model() {
    local model_name="$1"
    
    # Block unquantized models
    local disallowed=("llama3:latest" "llama3" "llama-3" "llama-3:latest")
    for dis in "${disallowed[@]}"; do
        if [ "${model_name,,}" == "${dis,,}" ]; then
            echo "ERROR: Model '$model_name' is unquantized and will crash RTX 3060!" >&2
            echo "Use a quantized model like 'llama3:8b-instruct-q4_K_M'" >&2
            return 1
        fi
    done
    
    # Check for quantization tags
    if [[ ! "$model_name" =~ (q4|q5|q6|q8) ]]; then
        echo "WARNING: Model '$model_name' does not appear to be quantized!" >&2
        echo "Quantized models should contain: q4, q5, q6, or q8" >&2
        echo "Recommended: llama3:8b-instruct-q4_K_M" >&2
        read -p "Continue anyway? (y/N): " response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    return 0
}

# Validate model name
echo "Validating model name: $MODEL"
if ! validate_model "$MODEL"; then
    echo "Aborting model pull."
    exit 1
fi

# Check if container is running
echo "Checking if container '$CONTAINER_NAME' is running..."
if ! docker ps --filter "name=$CONTAINER_NAME" --format "{{.Status}}" | grep -q .; then
    echo "ERROR: Container '$CONTAINER_NAME' is not running!" >&2
    echo "Start the container first with: docker compose up -d ollama" >&2
    exit 1
fi

CONTAINER_STATUS=$(docker ps --filter "name=$CONTAINER_NAME" --format "{{.Status}}")
echo "Container is running: $CONTAINER_STATUS"

# Pull the model
echo "Pulling model '$MODEL' into container '$CONTAINER_NAME'..."
echo "This may take several minutes depending on your internet connection..."

if docker exec "$CONTAINER_NAME" ollama pull "$MODEL"; then
    echo ""
    echo "SUCCESS: Model '$MODEL' pulled successfully!"
    
    # List installed models
    echo ""
    echo "Installed models:"
    docker exec "$CONTAINER_NAME" ollama list
else
    echo ""
    echo "ERROR: Failed to pull model. Check the error messages above." >&2
    exit 1
fi
