# PowerShell script to start Ollama container with GPU verification
# Includes model pulling with validation

param(
    [string]$Model = "llama3:8b-instruct-q4_K_M",
    [switch]$SkipGPUCheck,
    [switch]$SkipModelPull
)

$ContainerName = "ollama"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Ollama Docker Setup Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# GPU Verification
if (-not $SkipGPUCheck) {
    Write-Host "Step 1: Verifying GPU access..." -ForegroundColor Cyan
    try {
        $gpuTest = docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "GPU access verified!" -ForegroundColor Green
            Write-Host $gpuTest
        } else {
            Write-Host "WARNING: GPU access test failed!" -ForegroundColor Yellow
            Write-Host "Make sure NVIDIA Container Toolkit is installed and Docker Desktop uses WSL2 backend" -ForegroundColor Yellow
            $response = Read-Host "Continue anyway? (y/N)"
            if ($response -ne "y" -and $response -ne "Y") {
                exit 1
            }
        }
    } catch {
        Write-Host "WARNING: Could not verify GPU access: $_" -ForegroundColor Yellow
        Write-Host "Continuing anyway..." -ForegroundColor Yellow
    }
    Write-Host ""
}

# Start container
Write-Host "Step 2: Starting Ollama container..." -ForegroundColor Cyan
try {
    docker compose up -d ollama
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Container started successfully!" -ForegroundColor Green
    } else {
        Write-Host "ERROR: Failed to start container" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "ERROR: Exception starting container: $_" -ForegroundColor Red
    exit 1
}

# Wait for container to be healthy
Write-Host ""
Write-Host "Step 3: Waiting for container to be healthy..." -ForegroundColor Cyan
$maxWait = 120  # seconds
$waited = 0
$interval = 5

while ($waited -lt $maxWait) {
    $health = docker inspect --format='{{.State.Health.Status}}' $ContainerName 2>$null
    if ($health -eq "healthy") {
        Write-Host "Container is healthy!" -ForegroundColor Green
        break
    }
    Write-Host "Waiting... ($waited/$maxWait seconds)" -ForegroundColor Yellow
    Start-Sleep -Seconds $interval
    $waited += $interval
}

if ($waited -ge $maxWait) {
    Write-Host "WARNING: Container did not become healthy within $maxWait seconds" -ForegroundColor Yellow
    Write-Host "Check logs with: docker logs $ContainerName" -ForegroundColor Yellow
}

# Model pulling
if (-not $SkipModelPull) {
    Write-Host ""
    Write-Host "Step 4: Pulling model..." -ForegroundColor Cyan
    Write-Host "CRITICAL: RTX 3060 requires quantized models (Q4 or Q5)" -ForegroundColor Yellow
    Write-Host "DO NOT use 'llama3:latest' - it will cause OOM errors!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Default model: $Model" -ForegroundColor Cyan
    $customModel = Read-Host "Enter model name (or press Enter to use default)"
    
    if ($customModel) {
        $Model = $customModel
    }
    
    # Run the pull script with validation
    & "$PSScriptRoot\pull_ollama_model.ps1" -Model $Model -ContainerName $ContainerName
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Setup Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Ollama is running at: http://localhost:11434" -ForegroundColor Green
Write-Host "Test with: curl http://localhost:11434/api/tags" -ForegroundColor Cyan
Write-Host ""
Write-Host "To view logs: docker logs -f $ContainerName" -ForegroundColor Cyan
Write-Host "To stop: docker compose stop ollama" -ForegroundColor Cyan
