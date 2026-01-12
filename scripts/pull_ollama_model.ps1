# PowerShell script to pull quantized Ollama model into container
# CRITICAL: This script validates model names to prevent pulling unquantized models

param(
    [string]$Model = "llama3:8b-instruct-q4_K_M",
    [string]$ContainerName = "ollama"
)

# Function to validate model name
function Test-ModelName {
    param([string]$ModelName)
    
    # Block unquantized models
    $disallowed = @("llama3:latest", "llama3", "llama-3", "llama-3:latest")
    if ($disallowed -contains $ModelName.ToLower()) {
        Write-Host "ERROR: Model '$ModelName' is unquantized and will crash RTX 3060!" -ForegroundColor Red
        Write-Host "Use a quantized model like 'llama3:8b-instruct-q4_K_M'" -ForegroundColor Yellow
        return $false
    }
    
    # Check for quantization tags
    $allowedTags = @("q4", "q5", "q6", "q8")
    $hasQuantization = $false
    foreach ($tag in $allowedTags) {
        if ($ModelName -match $tag) {
            $hasQuantization = $true
            break
        }
    }
    
    if (-not $hasQuantization) {
        Write-Host "WARNING: Model '$ModelName' does not appear to be quantized!" -ForegroundColor Yellow
        Write-Host "Quantized models should contain: q4, q5, q6, or q8" -ForegroundColor Yellow
        Write-Host "Recommended: llama3:8b-instruct-q4_K_M" -ForegroundColor Yellow
        $response = Read-Host "Continue anyway? (y/N)"
        if ($response -ne "y" -and $response -ne "Y") {
            return $false
        }
    }
    
    return $true
}

# Validate model name
Write-Host "Validating model name: $Model" -ForegroundColor Cyan
if (-not (Test-ModelName -ModelName $Model)) {
    Write-Host "Aborting model pull." -ForegroundColor Red
    exit 1
}

# Check if container is running
Write-Host "Checking if container '$ContainerName' is running..." -ForegroundColor Cyan
$containerStatus = docker ps --filter "name=$ContainerName" --format "{{.Status}}"
if (-not $containerStatus) {
    Write-Host "ERROR: Container '$ContainerName' is not running!" -ForegroundColor Red
    Write-Host "Start the container first with: docker compose up -d ollama" -ForegroundColor Yellow
    exit 1
}

Write-Host "Container is running: $containerStatus" -ForegroundColor Green

# Pull the model
Write-Host "Pulling model '$Model' into container '$ContainerName'..." -ForegroundColor Cyan
Write-Host "This may take several minutes depending on your internet connection..." -ForegroundColor Yellow

try {
    docker exec $ContainerName ollama pull $Model
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`nSUCCESS: Model '$Model' pulled successfully!" -ForegroundColor Green
        
        # List installed models
        Write-Host "`nInstalled models:" -ForegroundColor Cyan
        docker exec $ContainerName ollama list
    } else {
        Write-Host "`nERROR: Failed to pull model. Check the error messages above." -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "`nERROR: Exception occurred: $_" -ForegroundColor Red
    exit 1
}
