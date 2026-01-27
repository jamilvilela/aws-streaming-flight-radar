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
if [ -z "$OPENSKY_USERNAME" ] || [ -z "$OPENSKY_PASSWORD" ]; then
    echo -e "${RED}❌ Credenciais OpenSky não estão definidas em .env${NC}"
    echo "   Edite .env e adicione OPENSKY_USERNAME e OPENSKY_PASSWORD"
    exit 1
fi

# Convert to Terraform variables (TF_VAR_*)
export TF_VAR_opensky_username="$OPENSKY_USERNAME"
export TF_VAR_opensky_password="$OPENSKY_PASSWORD"

# Export AWS region if set
if [ -n "$AWS_REGION" ]; then
    export TF_VAR_region="$AWS_REGION"
fi

echo -e "${GREEN}🔐 Credenciais configuradas como variáveis Terraform${NC}"
echo "   TF_VAR_opensky_username: ${OPENSKY_USERNAME:0:3}***"
echo "   TF_VAR_opensky_password: ${OPENSKY_PASSWORD:0:3}***"
echo -e "${BLUE}ℹ️  Terraform usa automaticamente: TF_VAR_* > terraform.tfvars > defaults${NC}"
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
# STEP 3: Navigate to infra directory
# =============================================================================
if [ ! -d "infra" ]; then
    echo -e "${RED}❌ Diretório infra/ não encontrado!${NC}"
    echo "   Execute este script da raiz do projeto"
    exit 1
fi

cd infra || exit 1
echo -e "${BLUE}📁 Mudado para diretório: $(pwd)${NC}"

set +a

# =============================================================================
# STEP 4: Terraform init
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
# STEP 5: Terraform validate
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
# STEP 6: Terraform plan
# =============================================================================
echo -e "${BLUE}Step 3: terraform plan${NC}"

terraform plan -var-file="tfvars/terraform.tfvars" -out=tfplan
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ terraform plan falhou${NC}"
    exit 1
fi
echo -e "${GREEN}✅ terraform plan concluído${NC}"
echo ""

# =============================================================================
# STEP 7: Terraform apply
# =============================================================================
echo -e "${BLUE}Step 4: terraform apply${NC}"

terraform apply -var-file="tfvars/terraform.tfvars" -auto-approve tfplan
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ terraform apply falhou${NC}"
    exit 1
fi
echo -e "${GREEN}✅ terraform apply concluído com sucesso!${NC}"
echo ""

# =============================================================================
# STEP 8: Post-deployment validation
# =============================================================================
echo -e "${BLUE}📋 Validação pós-deployment:${NC}"

# Check if Secrets Manager secret was created
echo -e "${BLUE}  • Verificando AWS Secrets Manager...${NC}"
SECRET_ARN=$(terraform output -raw opensky_secret_arn 2>/dev/null)
if [ -n "$SECRET_ARN" ]; then
    echo -e "${GREEN}    ✅ Secret criado: $SECRET_ARN${NC}"
else
    echo -e "${YELLOW}    ⚠️  Não foi possível recuperar ARN do secret${NC}"
fi

# Check if Lambda function was created
echo -e "${BLUE}  • Verificando AWS Lambda...${NC}"
LAMBDA_FUNCTIONS=$(terraform output -json lambda_arns 2>/dev/null)
if [ -n "$LAMBDA_FUNCTIONS" ]; then
    echo -e "${GREEN}    ✅ Lambda functions criadas${NC}"
else
    echo -e "${YELLOW}    ⚠️  Não foi possível recuperar ARNs do Lambda${NC}"
fi

echo ""
echo -e "${GREEN}🎉 Deployment concluído com sucesso!${NC}"
echo ""
echo -e "${BLUE}Próximos passos:${NC}"
echo "  1. Verifique os logs: aws logs tail /aws/lambda/flight-radar-stream-ingest-flights --follow"
echo "  2. Teste o Lambda: aws lambda invoke --function-name flight-radar-stream-ingest-flights /tmp/response.json"
echo "  3. Verifique o Kinesis: aws kinesis describe-stream --stream-name flight-radar-stream-flights"
echo ""
