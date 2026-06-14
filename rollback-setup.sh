#!/bin/bash
# rollback-setup.sh - Destroy all Terraform resources
# Usage: ./rollback-setup.sh

set -a

export AWS_PAGER=""  # disable AWS CLI pager (avoids Enter-key prompts on JSON output)

# =============================================================================
# STEP 1: Load environment variables from .env (optional)
# =============================================================================
if [ -f .env ]; then
    echo "📂 Carregando variáveis de .env..."
    source .env
    
    # Convert to Terraform variables
    export TF_VAR_opensky_client_id="$OPENSKY_CLIENT_ID"
    export TF_VAR_opensky_client_secret="$OPENSKY_CLIENT_SECRET"
    
    echo "✅ Variáveis carregadas com sucesso!"
fi

# =============================================================================
# STEP 2: Navigate to infra directory
# =============================================================================
if [ ! -d "infra" ]; then
    echo "❌ Diretório infra/ não encontrado!"
    echo "   Execute este script da raiz do projeto"
    exit 1
fi

cd infra || exit 1
echo "📁 Mudado para diretório: $(pwd)"

set +a

# =============================================================================
# STEP 3: Create final RDS snapshot before destruction
# =============================================================================
RDS_IDENTIFIER="${PROJECT_NAME:-flight-radar-stream}-postgres"
SNAPSHOT_ID="${RDS_IDENTIFIER}-snapshot-$(date +%Y%m%d-%H%M%S)"
SNAPSHOT_FILE=".rds-snapshot-id"

echo ""
echo "💾 Criando snapshot do RDS ($RDS_IDENTIFIER) antes da destruição..."
echo "   Snapshot: $SNAPSHOT_ID"

if aws rds describe-db-instances --db-instance-identifier "$RDS_IDENTIFIER" &>/dev/null; then
    aws rds create-db-snapshot \
        --db-instance-identifier "$RDS_IDENTIFIER" \
        --db-snapshot-identifier "$SNAPSHOT_ID"

    echo "⏳ Aguardando snapshot ficar disponível..."
    aws rds wait db-snapshot-available \
        --db-instance-identifier "$RDS_IDENTIFIER" \
        --db-snapshot-identifier "$SNAPSHOT_ID"

    echo "$SNAPSHOT_ID" > "$SNAPSHOT_FILE"
    echo "✅ Snapshot salvo: $SNAPSHOT_ID"
else
    echo "⚠️  Instância RDS $RDS_IDENTIFIER não encontrada. Pulando snapshot."
fi

# =============================================================================
# STEP 4: Terraform destroy with confirmation
# =============================================================================
echo ""
echo "⚠️  AVISO: Você está prestes a DESTRUIR todos os recursos AWS!"
echo "   Projeto: flight-radar-stream"
echo "   Ambiente: production"
echo ""
# echo "Digite 'sim' para confirmar o rollback (destruição):"
# read confirmation

# if [ "$confirmation" != "sim" ]; then
#     echo "❌ Rollback cancelado!"
#     exit 0
# fi

echo ""
echo "🔥 Iniciando destruição dos recursos..."
echo ""

terraform destroy -var-file="tfvars/terraform.tfvars" -auto-approve

echo "🧹 Limpando Elastic IPs órfãos com tag Name=${PROJECT_NAME}-eip-nat..."

aws ec2 describe-addresses \
  --filters "Name=tag:Name,Values=${PROJECT_NAME}-eip-nat" \
  --query "Addresses[].AllocationId" \
  --output text | while read -r ALLOC_ID; do
    if [ -n "$ALLOC_ID" ]; then
      echo " - Releasing EIP $ALLOC_ID"
      aws ec2 release-address --allocation-id "$ALLOC_ID"
    fi
  done

if [ $? -ne 0 ]; then
    echo "❌ terraform destroy falhou"
    exit 1
fi

echo ""
echo "✅ Rollback concluído! Todos os recursos foram destruídos."
echo ""
