# PowerShell script to verify GPU access in Docker
# Tests NVIDIA runtime availability and displays GPU information

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "GPU Verification for Docker" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check Docker installation
Write-Host "Step 1: Checking Docker installation..." -ForegroundColor Cyan
try {
    $dockerVersion = docker --version
    Write-Host "Docker found: $dockerVersion" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Docker is not installed or not in PATH" -ForegroundColor Red
    exit 1
}

# Check Docker Compose
Write-Host ""
Write-Host "Step 2: Checking Docker Compose..." -ForegroundColor Cyan
try {
    $composeVersion = docker compose version
    Write-Host "Docker Compose found: $composeVersion" -ForegroundColor Green
} catch {
    Write-Host "WARNING: Docker Compose not found. Trying docker-compose..." -ForegroundColor Yellow
    try {
        $composeVersion = docker-compose --version
        Write-Host "docker-compose found: $composeVersion" -ForegroundColor Green
    } catch {
        Write-Host "ERROR: Docker Compose is not installed" -ForegroundColor Red
        exit 1
    }
}

# Test GPU access
Write-Host ""
Write-Host "Step 3: Testing GPU access in Docker..." -ForegroundColor Cyan
Write-Host "Running: docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi" -ForegroundColor Yellow
Write-Host ""

try {
    docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "SUCCESS: GPU access verified!" -ForegroundColor Green
        
        # Extract GPU info
        Write-Host ""
        Write-Host "GPU Information:" -ForegroundColor Cyan
        $gpuInfo = docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
        Write-Host $gpuInfo
        
        # Check VRAM
        $vramInfo = docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits
        $vramGB = [int]($vramInfo -replace '\s+', '')
        
        Write-Host ""
        if ($vramGB -lt 12000) {
            Write-Host "WARNING: GPU has $vramGB MB VRAM (< 12GB)" -ForegroundColor Yellow
            Write-Host "CRITICAL: You MUST use quantized models (Q4 or Q5)!" -ForegroundColor Red
            Write-Host "DO NOT use 'llama3:latest' - it will cause OOM errors!" -ForegroundColor Red
            Write-Host "Recommended: llama3:8b-instruct-q4_K_M (~4.5GB)" -ForegroundColor Yellow
        } else {
            Write-Host "GPU has $vramGB MB VRAM" -ForegroundColor Green
            Write-Host "Still recommended to use quantized models for better performance" -ForegroundColor Yellow
        }
    } else {
        Write-Host ""
        Write-Host "ERROR: GPU access test failed!" -ForegroundColor Red
        Write-Host ""
        Write-Host "Troubleshooting steps:" -ForegroundColor Yellow
        Write-Host "1. Ensure NVIDIA drivers are installed (latest version)" -ForegroundColor White
        Write-Host "2. Install NVIDIA Container Toolkit:" -ForegroundColor White
        Write-Host "   https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html" -ForegroundColor White
        Write-Host "3. Ensure Docker Desktop uses WSL2 backend (Settings > General > Use WSL 2)" -ForegroundColor White
        Write-Host "4. Restart Docker Desktop after installing NVIDIA Container Toolkit" -ForegroundColor White
        exit 1
    }
} catch {
    Write-Host ""
    Write-Host "ERROR: Exception during GPU test: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Make sure:" -ForegroundColor Yellow
    Write-Host "- NVIDIA Container Toolkit is installed" -ForegroundColor White
    Write-Host "- Docker Desktop uses WSL2 backend" -ForegroundColor White
    Write-Host "- Docker Desktop is restarted after toolkit installation" -ForegroundColor White
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Verification Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
