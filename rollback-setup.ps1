# rollback-setup.ps1 - Destroy all Terraform resources (Windows)
# Usage: .\rollback-setup.ps1

# ===================================================================
# Color functions
# ===================================================================
function Write-Success {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Green
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Red
}

function Write-Warning-Custom {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Yellow
}

function Write-Info {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
}

# ===================================================================
# STEP 1: Load environment variables from .env (optional)
# ===================================================================
if (Test-Path ".env") {
    Write-Info "📂 Carregando variáveis de .env..."
    
    # Read and parse .env file
    $envContent = Get-Content ".env"
    
    foreach ($line in $envContent) {
        $line = $line.Trim()
        
        # Skip empty lines and comments
        if ($line -and -not $line.StartsWith("#")) {
            $parts = $line -split '=', 2
            
            if ($parts.Count -eq 2) {
                $key = $parts[0].Trim()
                $value = $parts[1].Trim()
                
                # Remove quotes if present
                $value = $value -replace '^["'']|["'']$', ''
                
                # Set environment variable
                [Environment]::SetEnvironmentVariable($key, $value, "Process")
            }
        }
    }
    
    # Convert to Terraform variables
    $env:TF_VAR_opensky_username = $env:OPENSKY_USERNAME
    $env:TF_VAR_opensky_password = $env:OPENSKY_PASSWORD
    
    Write-Success "✅ Variáveis carregadas com sucesso!"
}

# ===================================================================
# STEP 2: Navigate to infra directory
# ===================================================================
if (-not (Test-Path "infra")) {
    Write-Error-Custom "❌ Diretório infra/ não encontrado!"
    Write-Warning-Custom "   Execute este script da raiz do projeto"
    exit 1
}

Set-Location "infra"
Write-Info "📁 Mudado para diretório: $(Get-Location)"

# ===================================================================
# STEP 3: Terraform destroy with confirmation
# ===================================================================
Write-Host ""
Write-Warning-Custom "⚠️  AVISO: Você está prestes a DESTRUIR todos os recursos AWS!"
Write-Host "   Projeto: flight-radar-stream"
Write-Host "   Ambiente: production"
Write-Host ""

$confirmation = Read-Host "Digite 'sim' para confirmar o rollback (destruição)"

if ($confirmation -ne "sim") {
    Write-Error-Custom "❌ Rollback cancelado!"
    exit 0
}

Write-Host ""
Write-Warning-Custom "🔥 Iniciando destruição dos recursos..."
Write-Host ""

terraform destroy -var-file="tfvars/terraform.tfvars" -auto-approve

if ($LASTEXITCODE -ne 0) {
    Write-Error-Custom "❌ terraform destroy falhou"
    exit 1
}

Write-Host ""
Write-Success "✅ Rollback concluído! Todos os recursos foram destruídos."
Write-Host ""
