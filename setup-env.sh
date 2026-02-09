#!/bin/bash
# setup-env.sh - Load environment variables and deploy Terraform
# Usage: ./setup-env.sh
# Always runs: init → validate → plan → apply (auto-approve)

set -a  # Export all variables

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# STEP 1: Load environment variables from .env
# =============================================================================
echo -e "${BLUE}📂 Carregando variáveis de .env...${NC}"

if [ ! -f .env ]; then
    echo -e "${RED}❌ Erro: Arquivo .env não encontrado!${NC}"
    echo "   Copie .env.example para .env e preencha com seus valores"
    echo "   cp .env.example .env"
    exit 1
fi

source .env
echo -e "${GREEN}✅ Variáveis carregadas com sucesso!${NC}"

# Verify OpenSky credentials are set
if [ -z "$OPENSKY_CLIENT_ID" ] || [ -z "$OPENSKY_CLIENT_SECRET" ]; then
    echo -e "${RED}❌ Credenciais OpenSky não estão definidas em .env${NC}"
    echo "   Edite .env e adicione OPENSKY_CLIENT_ID e OPENSKY_CLIENT_SECRET"
    exit 1
fi

# Convert to Terraform variables (TF_VAR_*)
export TF_VAR_opensky_client_id="$OPENSKY_CLIENT_ID"
export TF_VAR_opensky_client_secret="$OPENSKY_CLIENT_SECRET"

# Export AWS region if set
if [ -n "$AWS_REGION" ]; then
    export TF_VAR_region="$AWS_REGION"
fi

echo -e "${GREEN}🔐 Credenciais configuradas como variáveis Terraform${NC}"
echo "   TF_VAR_opensky_client_id: ${OPENSKY_CLIENT_ID:0:3}***"
echo "   TF_VAR_opensky_client_secret: ${OPENSKY_CLIENT_SECRET:0:3}***"
echo -e "${BLUE}ℹ️  Terraform usa automaticamente: TF_VAR_* > terraform.tfvars > defaults${NC}"

# =============================================================================
# STEP 2: Verify AWS credentials are set
# =============================================================================
echo ""
echo -e "${BLUE}🔑 Verificando credenciais AWS...${NC}"

if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo -e "${YELLOW}⚠️  AWS credentials não encontradas${NC}"
    echo "   Configure com: export AWS_ACCESS_KEY_ID=xxx"
    echo "                 export AWS_SECRET_ACCESS_KEY=xxx"
    echo "   Ou use: aws configure"
    echo "   Continuando (assumindo AWS credentials via IAM role)..."
else
    echo -e "${GREEN}✅ AWS credentials encontradas${NC}"
fi

# =============================================================================
# STEP 3: Build/Update Python Lambda Layer dependencies (app/layers/python/)
# =============================================================================
echo ""
echo -e "${BLUE}📦 Construindo dependências da Lambda Layer (app/layers/python)...${NC}"

PYTHON_BIN="${PYTHON_BIN:-python3}"
LAYER_ROOT_DIR="app/layers"
LAYER_SITEPACKAGES_DIR="$LAYER_ROOT_DIR/python"
REQ_FILE="app/requirements.txt"
# LOCAL_OPENSKY_PACKAGE_DIR="app/opensky-api/python"  # ajuste se o caminho for diferente

# Verifica se requirements.txt existe
if [ ! -f "$REQ_FILE" ]; then
  echo -e "${RED}❌ Arquivo de requirements não encontrado em '$REQ_FILE'${NC}"
  echo " Crie ou corrija o caminho do requirements.txt."
  exit 1
fi

# Garante que diretório raiz da layer existe
mkdir -p "$LAYER_SITEPACKAGES_DIR"

# Limpa dependências anteriores (opcional, mas recomendado)
echo -e "${BLUE}🧹 Limpando dependências anteriores da layer...${NC}"
rm -rf "$LAYER_SITEPACKAGES_DIR"/*
rm -rf "$LAYER_SITEPACKAGES_DIR"/.[!.]* 2>/dev/null || true

# Entra na pasta app/layers
pushd "$LAYER_ROOT_DIR" >/dev/null 2>&1

echo -e "${BLUE}📥 Instalando dependências de '$REQ_FILE' em '$LAYER_SITEPACKAGES_DIR'...${NC}"
"$PYTHON_BIN" -m pip install -r ../requirements.txt -t python

# # Se existir o pacote local opensky-api/python, instala também na layer
# if [ -d "../opensky-api/python" ]; then
#   echo -e "${BLUE}📥 Instalando pacote local opensky-api em '$LAYER_SITEPACKAGES_DIR'...${NC}"
#   "$PYTHON_BIN" -m pip install ../opensky-api/python -t python
# else
#   echo -e "${YELLOW}⚠️ Diretório '../opensky-api/python' não encontrado; pulando instalação de python_opensky local${NC}"
# fi

popd >/dev/null 2>&1

echo -e "${GREEN}✅ Dependências da Lambda Layer instaladas em '$LAYER_SITEPACKAGES_DIR'${NC}"

# =============================================================================
# STEP 4: Navigate to infra directory
# =============================================================================
echo ""
echo -e "${BLUE}📁 Navegando para diretório infra/...${NC}"

if [ ! -d "infra" ]; then
    echo -e "${RED}❌ Diretório infra/ não encontrado!${NC}"
    echo "   Execute este script a partir da raiz do projeto."
    exit 1
fi

cd infra || exit 1
echo -e "${GREEN}✅ Agora em: $(pwd)${NC}"

set +a  # não precisa mais exportar automático

# Garante que o arquivo de variáveis exista
TFVARS_FILE="tfvars/terraform.tfvars"
if [ ! -f "$TFVARS_FILE" ]; then
    echo -e "${RED}❌ Arquivo de variáveis '$TFVARS_FILE' não encontrado!${NC}"
    echo "   Crie-o a partir do template, por exemplo:"
    echo "   cp tfvars/terraform.tfvars.example tfvars/terraform.tfvars"
    exit 1
fi

# =============================================================================
# STEP 5: Terraform init
# =============================================================================
echo ""
echo -e "${BLUE}🚀 Iniciando deployment Terraform...${NC}"
echo ""
echo -e "${BLUE}Step 1: terraform init${NC}"

terraform init
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ terraform init falhou${NC}"
    exit 1
fi
echo -e "${GREEN}✅ terraform init concluído${NC}"
echo ""

# =============================================================================
# STEP 6: Terraform validate
# =============================================================================
echo -e "${BLUE}Step 2: terraform validate${NC}"

terraform validate
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ terraform validate falhou${NC}"
    exit 1
fi
echo -e "${GREEN}✅ terraform validate concluído${NC}"
echo ""

# =============================================================================
# STEP 7: Terraform plan
# =============================================================================
echo -e "${BLUE}Step 3: terraform plan${NC}"

terraform plan -var-file="$TFVARS_FILE" -out=tfplan
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ terraform plan falhou${NC}"
    exit 1
fi
echo -e "${GREEN}✅ terraform plan concluído${NC}"
echo ""

# =============================================================================
# STEP 8: Terraform apply
# =============================================================================
echo -e "${BLUE}Step 4: terraform apply${NC}"

terraform apply -var-file="$TFVARS_FILE" -auto-approve tfplan
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ terraform apply falhou${NC}"
    exit 1
fi
echo -e "${GREEN}✅ terraform apply concluído com sucesso!${NC}"
echo ""

# =============================================================================
# STEP 9: Post-deployment validation
# =============================================================================
echo -e "${BLUE}📋 Validação pós-deployment:${NC}"

# Garantir que jq exista (usado para parsear JSON do terraform output)
if ! command -v jq >/dev/null 2>&1; then
  echo -e "${YELLOW}⚠️ jq não encontrado. Instale jq para validação detalhada dos outputs.${NC}"
  echo -e "${YELLOW}   Ex.: sudo apt-get install jq  ou  brew install jq${NC}"
fi

# -----------------------------------------------------------------------------
# Check if Secrets Manager secret was created (using output: secrets_manager_info)
# -----------------------------------------------------------------------------
echo -e "${BLUE} • Verificando AWS Secrets Manager...${NC}"

SECRET_INFO_JSON=$(terraform output -json secrets_manager_info 2>/dev/null || echo "")

if [ -n "$SECRET_INFO_JSON" ] && [ "$SECRET_INFO_JSON" != "null" ]; then
  if command -v jq >/dev/null 2>&1; then
    SECRET_ARN=$(echo "$SECRET_INFO_JSON" | jq -r '.opensky_credentials.secret_arn // empty')
    if [ -n "$SECRET_ARN" ] && [ "$SECRET_ARN" != "null" ]; then
      echo -e "${GREEN} ✅ Secret criado: $SECRET_ARN${NC}"
    else
      echo -e "${YELLOW} ⚠️ Output 'secrets_manager_info' encontrado, mas não foi possível extrair 'secret_arn'${NC}"
      echo -e "${YELLOW}    Valor bruto:${NC} $SECRET_INFO_JSON"
    fi
  else
    echo -e "${GREEN} ✅ Output 'secrets_manager_info' encontrado (instale jq para ver detalhes)${NC}"
  fi
else
  echo -e "${YELLOW} ⚠️ Não foi possível recuperar informações do Secrets Manager (output 'secrets_manager_info')${NC}"
fi

# -----------------------------------------------------------------------------
# Check if Lambda functions were created (using output: lambda_functions_summary)
# -----------------------------------------------------------------------------
echo -e "${BLUE} • Verificando AWS Lambda...${NC}"

LAMBDA_SUMMARY_JSON=$(terraform output -json lambda_functions_summary 2>/dev/null || echo "")

if [ -n "$LAMBDA_SUMMARY_JSON" ] && [ "$LAMBDA_SUMMARY_JSON" != "null" ]; then
  if command -v jq >/dev/null 2>&1; then
    LAMBDA_COUNT=$(echo "$LAMBDA_SUMMARY_JSON" | jq 'keys | length')

    if [ "$LAMBDA_COUNT" -gt 0 ]; then
      echo -e "${GREEN} ✅ ${LAMBDA_COUNT} Lambda function(s) criada(s):${NC}"
      echo "$LAMBDA_SUMMARY_JSON" \
        | jq -r 'to_entries[] | "   - \(.key): \(.value.function_name) (\(.value.function_arn))"'
    else
      echo -e "${YELLOW} ⚠️ Output 'lambda_functions_summary' vazio${NC}"
    fi
  else
    echo -e "${GREEN} ✅ Output 'lambda_functions_summary' encontrado (instale jq para ver detalhes)${NC}"
  fi
else
  echo -e "${YELLOW} ⚠️ Não foi possível recuperar informações das Lambdas (output 'lambda_functions_summary')${NC}"
fi

echo ""
echo -e "${GREEN}🎉 Deployment concluído com sucesso!${NC}"
echo ""
echo -e "${BLUE}Próximos passos:${NC}"
echo " 1. Verifique os logs: aws logs tail /aws/lambda/flight-radar-stream-ingest-flights --follow"
echo " 2. Teste o Lambda: aws lambda invoke --function-name flight-radar-stream-ingest-flights /tmp/response.json"
echo " 3. Verifique o Kinesis: aws kinesis describe-stream --stream-name flight-radar-kinesis-stream-flights"
echo ""