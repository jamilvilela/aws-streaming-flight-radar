# setup-env.ps1 - Load environment variables and deploy Terraform (Windows)
# Usage: .\setup-env.ps1
# Always runs: init → validate → plan → apply (auto-approve)

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
# STEP 1: Load environment variables from .env
# ===================================================================
Write-Info "📂 Carregando variáveis de .env..."

if (-not (Test-Path ".env")) {
    Write-Error-Custom "❌ Erro: Arquivo .env não encontrado!"
    Write-Warning-Custom "   Copie .env.example para .env"
    Write-Warning-Custom "   Copy-Item .env.example -Destination .env"
    exit 1
}

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

Write-Success "✅ Variáveis carregadas com sucesso!"

# ===================================================================
# STEP 2: Verify OpenSky credentials
# ===================================================================
if (-not $env:OPENSKY_USERNAME -or -not $env:OPENSKY_PASSWORD) {
    Write-Error-Custom "❌ Credenciais OpenSky não estão definidas em .env"
    Write-Warning-Custom "   Edite .env e adicione OPENSKY_USERNAME e OPENSKY_PASSWORD"
    exit 1
}

# Convert to Terraform variables (TF_VAR_*)
$env:TF_VAR_opensky_username = $env:OPENSKY_USERNAME
$env:TF_VAR_opensky_password = $env:OPENSKY_PASSWORD

if ($env:AWS_REGION) {
    $env:TF_VAR_region = $env:AWS_REGION
}

Write-Success "🔐 Credenciais configuradas como variáveis Terraform"
Write-Success "   TF_VAR_opensky_username: $($env:OPENSKY_USERNAME.Substring(0, 3))***"
Write-Success "   TF_VAR_opensky_password: $($env:OPENSKY_PASSWORD.Substring(0, 3))***"
Write-Info "ℹ️  Terraform usa automaticamente: TF_VAR_* > terraform.tfvars > defaults"

# ===================================================================
# STEP 4: Verify AWS credentials
# ===================================================================
Write-Host ""
Write-Info "🔑 Verificando credenciais AWS..."

if (-not $env:AWS_ACCESS_KEY_ID -or -not $env:AWS_SECRET_ACCESS_KEY) {
    Write-Warning-Custom "⚠️  AWS credentials não encontradas"
    Write-Info "   Configure com: `$env:AWS_ACCESS_KEY_ID = 'xxx'"
    Write-Info "                 `$env:AWS_SECRET_ACCESS_KEY = 'xxx'"
    Write-Info "   Ou use: aws configure"
    Write-Info "   Continuando (assumindo AWS credentials via IAM role)..."
} else {
    Write-Success "✅ AWS credentials encontradas"
}

# ===================================================================
# STEP 5: Navigate to infra directory
# ===================================================================
if (-not (Test-Path "infra")) {
    Write-Error-Custom "❌ Diretório infra/ não encontrado!"
    Write-Warning-Custom "   Execute este script da raiz do projeto"
    exit 1
}

Set-Location "infra"
Write-Info "📁 Mudado para diretório: $(Get-Location)"

# ===================================================================
# STEP 6: Terraform init
# ===================================================================
Write-Host ""
Write-Info "🚀 Iniciando deployment Terraform..."
Write-Host ""
Write-Info "Step 1: terraform init"

terraform init

if ($LASTEXITCODE -ne 0) {
    Write-Error-Custom "❌ terraform init falhou"
    exit 1
}
Write-Success "✅ terraform init concluído"
Write-Host ""

# ===================================================================
# STEP 7: Terraform validate
# ===================================================================
Write-Info "Step 2: terraform validate"

terraform validate

if ($LASTEXITCODE -ne 0) {
    Write-Error-Custom "❌ terraform validate falhou"
    exit 1
}
Write-Success "✅ terraform validate concluído"
Write-Host ""

# ===================================================================
# STEP 8: Terraform plan
# ===================================================================
Write-Info "Step 3: terraform plan"

terraform plan -var-file="tfvars/terraform.tfvars" -out=tfplan

if ($LASTEXITCODE -ne 0) {
    Write-Error-Custom "❌ terraform plan falhou"
    exit 1
}
Write-Success "✅ terraform plan concluído"
Write-Host ""

# ===================================================================
# STEP 9: Terraform apply
# ===================================================================
Write-Info "Step 4: terraform apply"

terraform apply -var-file="tfvars/terraform.tfvars" -auto-approve tfplan

if ($LASTEXITCODE -ne 0) {
    Write-Error-Custom "❌ terraform apply falhou"
    exit 1
}

Write-Success "✅ terraform apply concluído com sucesso!"
Write-Host ""

# ===================================================================
# STEP 10: Post-deployment validation
# ===================================================================
Write-Info "📋 Validação pós-deployment:"

# Check if Secrets Manager secret was created
Write-Info "  • Verificando AWS Secrets Manager..."
try {
    $secretArn = terraform output -raw opensky_secret_arn 2>$null
    if ($secretArn) {
        Write-Success "    ✅ Secret criado: $secretArn"
    } else {
        Write-Warning-Custom "    ⚠️  Não foi possível recuperar ARN do secret"
    }
} catch {
    Write-Warning-Custom "    ⚠️  Erro ao recuperar secret ARN"
}

# Check if Lambda function was created
Write-Info "  • Verificando AWS Lambda..."
try {
    $lambdaArns = terraform output -json lambda_arns 2>$null
    if ($lambdaArns) {
        Write-Success "    ✅ Lambda functions criadas"
    } else {
        Write-Warning-Custom "    ⚠️  Não foi possível recuperar ARNs do Lambda"
    }
} catch {
    Write-Warning-Custom "    ⚠️  Erro ao recuperar Lambda ARNs"
}

Write-Host ""
Write-Success "🎉 Deployment concluído com sucesso!"
Write-Host ""
Write-Info "Próximos passos:"
Write-Host "  1. Verifique os logs:"
Write-Host '     aws logs tail /aws/lambda/flight-radar-stream-ingest-flights --follow' -ForegroundColor Gray
Write-Host ""
Write-Host "  2. Teste o Lambda:"
Write-Host '     aws lambda invoke --function-name flight-radar-stream-ingest-flights C:\tmp\response.json' -ForegroundColor Gray
Write-Host ""
Write-Host "  3. Verifique o Kinesis:"
Write-Host '     aws kinesis describe-stream --stream-name flight-radar-kinesis-stream-flights' -ForegroundColor Gray
Write-Host ""