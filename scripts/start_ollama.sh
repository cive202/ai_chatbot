#!/bin/bash
# Bash script to start Ollama container with GPU verification
# Includes model pulling with validation

MODEL="${1:-llama3:8b-instruct-q4_K_M}"
SKIP_GPU_CHECK="${SKIP_GPU_CHECK:-false}"
SKIP_MODEL_PULL="${SKIP_MODEL_PULL:-false}"
CONTAINER_NAME="ollama"

# Detect docker compose command
if command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
else
    COMPOSE_CMD="docker compose"
fi

echo "========================================"
echo "Ollama Docker Setup Script"
echo "========================================"
echo ""

# GPU Verification
if [ "$SKIP_GPU_CHECK" != "true" ]; then
    echo "Step 1: Verifying GPU access..."
    if docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi &> /dev/null; then
        echo "GPU access verified!"
        docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi
    else
        echo "WARNING: GPU access test failed!"
        echo "Make sure NVIDIA Container Toolkit is installed"
        read -p "Continue anyway? (y/N): " response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    echo ""
fi

# Start container
echo "Step 2: Starting Ollama container..."
if $COMPOSE_CMD up -d ollama; then
    echo "Container started successfully!"
else
    echo "ERROR: Failed to start container" >&2
    exit 1
fi

# Wait for container to be healthy
echo ""
echo "Step 3: Waiting for container to be healthy..."
MAX_WAIT=120
WAITED=0
INTERVAL=5

while [ $WAITED -lt $MAX_WAIT ]; do
    HEALTH=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null)
    if [ "$HEALTH" == "healthy" ]; then
        echo "Container is healthy!"
        break
    fi
    echo "Waiting... ($WAITED/$MAX_WAIT seconds)"
    sleep $INTERVAL
    WAITED=$((WAITED + INTERVAL))
done

if [ $WAITED -ge $MAX_WAIT ]; then
    echo "WARNING: Container did not become healthy within $MAX_WAIT seconds"
    echo "Check logs with: docker logs $CONTAINER_NAME"
fi

# Model pulling
if [ "$SKIP_MODEL_PULL" != "true" ]; then
    echo ""
    echo "Step 4: Pulling model..."
    echo "CRITICAL: RTX 3060 requires quantized models (Q4 or Q5)"
    echo "DO NOT use 'llama3:latest' - it will cause OOM errors!"
    echo ""
    echo "Default model: $MODEL"
    read -p "Enter model name (or press Enter to use default): " custom_model
    
    if [ -n "$custom_model" ]; then
        MODEL="$custom_model"
    fi
    
    # Run the pull script with validation
    bash "$(dirname "$0")/pull_ollama_model.sh" "$MODEL" "$CONTAINER_NAME"
fi

echo ""
echo "========================================"
echo "Setup Complete!"
echo "========================================"
echo ""
echo "Ollama is running at: http://localhost:11434"
echo "Test with: curl http://localhost:11434/api/tags"
echo ""
echo "To view logs: docker logs -f $CONTAINER_NAME"
echo "To stop: $COMPOSE_CMD stop ollama"
