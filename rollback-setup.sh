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
RDS_IDENTIFIER="${PROJECT_NAME}-postgres"

SNAPSHOT_ID="${RDS_IDENTIFIER}-snapshot-$(date +%Y%m%d-%H%M%S)"
SNAPSHOT_FILE=".rds-snapshot-id"
REGION="${AWS_REGION:-us-east-1}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
wait_for_snapshot() {
    local SID="$1"
    echo "⏳ Aguardando snapshot $SID ficar available..."
    aws rds wait db-snapshot-available \
        --db-instance-identifier "$RDS_IDENTIFIER" \
        --db-snapshot-identifier "$SID"
}

# (ensure_export_kms_key e ensure_export_role foram removidos)

# =============================================================================
# STEP 3: Create final RDS snapshot
# =============================================================================
echo ""
echo "💾 STEP 3 — Criando snapshot final do RDS"
echo "   Snapshot: $SNAPSHOT_ID"

if aws rds describe-db-instances --db-instance-identifier "$RDS_IDENTIFIER" &>/dev/null; then
    aws rds create-db-snapshot \
        --db-instance-identifier "$RDS_IDENTIFIER" \
        --db-snapshot-identifier "$SNAPSHOT_ID"
    wait_for_snapshot "$SNAPSHOT_ID"
    echo "$SNAPSHOT_ID" > "$SNAPSHOT_FILE"
    echo "✅ Snapshot salvo: $SNAPSHOT_ID"
else
    echo "⚠️  Instância $RDS_IDENTIFIER não encontrada."
    echo "   Procure snapshots manuais existentes para exportar..."
    # Tenta usar o snapshot mais recente
    SNAPSHOT_ID=$(aws rds describe-db-snapshots \
        --snapshot-type manual \
        --query "reverse(sort_by(DBSnapshots, &SnapshotCreateTime))[0].DBSnapshotIdentifier" \
        --output text 2>/dev/null)
    if [ -n "$SNAPSHOT_ID" ] && [ "$SNAPSHOT_ID" != "None" ]; then
        echo "   Usando snapshot existente: $SNAPSHOT_ID"
        echo "$SNAPSHOT_ID" > "$SNAPSHOT_FILE"
    else
        echo "⚠️  Nenhum snapshot manual encontrado."
        SNAPSHOT_ID=""
    fi
fi

# =============================================================================
# STEP 4: Terraform destroy (TUDO, incluindo RDS)
# =============================================================================
echo ""
echo "⚠️  STEP 4 — DESTRUINDO todos os recursos via Terraform"
echo "   Projeto: $PROJECT_NAME | Ambiente: production"
echo "   Snapshot '$SNAPSHOT_ID' preservado no RDS para restore."
echo ""

echo "🔥 Destruindo recursos..."
terraform destroy -var-file="tfvars/terraform.tfvars" -auto-approve

DESTROY_EXIT=$?

# =============================================================================
# STEP 5: Cleanup orphaned resources
# =============================================================================
echo ""
echo "🧹 STEP 5 — Limpando recursos órfãos"

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
echo "  📌 RDS PostgreSQL foi deletado."
echo ""
echo "  💾 Snapshot RDS preservado para restore:"
echo "     $SNAPSHOT_ID"
echo ""
echo "  ▶️  Para RECRIAR o ambiente com o snapshot salvo:"
echo "     ./setup-env.sh"
echo ""
echo "  O setup-env.sh detectará automaticamente o snapshot manual"
echo "  mais recente e configurará TF_VAR_rds_snapshot_identifier."
echo ""
echo "═══════════════════════════════════════════════════════════════"
