#!/bin/bash
# rollback-setup.sh - Cria snapshot final e DESTRÓI tudo
# Usage: ./rollback-setup.sh
#
# Fluxo:
#   1. Cria snapshot manual do RDS
#   2. terraform destroy (RDS incluso)
#   3. Snapshot preservado no RDS para restore via setup-env.sh

set -a

export AWS_PAGER=""  # disable AWS CLI pager

# =============================================================================
# STEP 1: Load environment variables from .env
# =============================================================================
if [ -f .env ]; then
    echo "📂 Carregando variáveis de .env..."
    source .env
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
# Config
# =============================================================================
PROJECT_NAME="${PROJECT_NAME:-flight-radar-stream}"
REGION="${AWS_REGION:-us-east-1}"

# =============================================================================
# STEP 3: Terraform destroy (TUDO, incluindo Aurora)
# skip_final_snapshot=false → Terraform cria snapshot final automático no destroy
# =============================================================================
echo ""
echo "⚠️  STEP 3 — DESTRUINDO todos os recursos via Terraform"
echo "   Projeto: $PROJECT_NAME | Ambiente: production"
echo "   (skip_final_snapshot=false → snapshot final automático será gerado)"
echo ""

echo "🔥 Destruindo recursos..."
terraform destroy -var-file="tfvars/terraform.tfvars" -auto-approve

DESTROY_EXIT=$?

# =============================================================================
# STEP 4: Cleanup orphaned resources
# =============================================================================
echo ""
echo "🧹 STEP 4 — Limpando recursos órfãos"

echo "   Elastic IPs (tag Name=${PROJECT_NAME}-eip-nat)..."
aws ec2 describe-addresses \
  --filters "Name=tag:Name,Values=${PROJECT_NAME}-eip-nat" \
  --region "$REGION" \
  --query "Addresses[].AllocationId" \
  --output text | while read -r ALLOC_ID; do
    if [ -n "$ALLOC_ID" ]; then
      echo "   - Liberando EIP $ALLOC_ID"
      aws ec2 release-address --allocation-id "$ALLOC_ID" --region "$REGION"
    fi
  done

if [ $DESTROY_EXIT -ne 0 ]; then
    echo "❌ terraform destroy falhou (código $DESTROY_EXIT)."
    echo "   Reveja os erros acima e execute manualmente se necessário."
    exit 1
fi

# =============================================================================
# STEP 6: Summary
# =============================================================================
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  ✅ Rollback concluído!"
echo ""
echo "  📌 Todos os recursos foram DESTRUÍDOS via Terraform."
echo "  📌 Aurora Serverless v2 foi deletado."
echo ""
echo "  💾 Cluster snapshot Aurora preservado para restore:"
echo "     $SNAPSHOT_ID"
echo ""
echo "  ▶️  Para RECRIAR o ambiente primeiro rode o setup:"
echo "     ./setup-env.sh"
echo ""
echo "  ▶️  Depois, restaure o snapshot Aurora com:"
