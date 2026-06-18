#!/bin/bash
# rollback-setup.sh - Stop RDS + destroy remaining resources
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
# STEP 3: Create final RDS snapshot before stopping
# =============================================================================
RDS_IDENTIFIER="${PROJECT_NAME:-flight-radar-stream}-postgres"
REPLICA_IDENTIFIER="${RDS_IDENTIFIER}-replica-1"
SNAPSHOT_ID="${RDS_IDENTIFIER}-snapshot-$(date +%Y%m%d-%H%M%S)"
SNAPSHOT_FILE=".rds-snapshot-id"
RDS_STATE_FILE=".rds-state-addresses"

echo ""
echo "💾 Criando snapshot do RDS ($RDS_IDENTIFIER) antes de parar..."
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
# STEP 4: Stop RDS instances (main + replica) — NOT destroy
# =============================================================================
echo ""
echo "⏹️  Parando instância RDS principal ($RDS_IDENTIFIER)..."
if aws rds describe-db-instances --db-instance-identifier "$RDS_IDENTIFIER" &>/dev/null; then
    aws rds stop-db-instance --db-instance-identifier "$RDS_IDENTIFIER" --no-force
    echo "⏳ Aguardando RDS principal parar..."
    aws rds wait db-instance-stopped --db-instance-identifier "$RDS_IDENTIFIER"
    echo "✅ RDS principal parado."
fi

echo ""
echo "⏹️  Parando réplica RDS ($REPLICA_IDENTIFIER)..."
if aws rds describe-db-instances --db-instance-identifier "$REPLICA_IDENTIFIER" &>/dev/null; then
    aws rds stop-db-instance --db-instance-identifier "$REPLICA_IDENTIFIER" --no-force
    echo "⏳ Aguardando réplica parar..."
    aws rds wait db-instance-stopped --db-instance-identifier "$REPLICA_IDENTIFIER"
    echo "✅ Réplica RDS parada."
fi

# =============================================================================
# STEP 5: Remove RDS instances from Terraform state so destroy não as toque
# =============================================================================
echo ""
echo "🗑️  Removendo RDS do estado do Terraform para preservá-las..."

terraform state list 2>/dev/null \
  | grep 'module.rds_postgres.aws_db_instance' \
  | tee "$RDS_STATE_FILE" \
  | while read -r ADDR; do
      echo "   Removendo: $ADDR"
      terraform state rm "$ADDR"
    done

# =============================================================================
# STEP 6: Terraform destroy (todos os recursos EXCETO RDS)
# =============================================================================
echo ""
echo "⚠️  AVISO: Você está prestes a DESTRUIR os recursos AWS restantes!"
echo "   O RDS PostgreSQL foi PARADO e preservado."
echo "   Projeto: flight-radar-stream"
echo "   Ambiente: production"
echo ""

echo "🔥 Destruindo demais recursos..."
terraform destroy -var-file="tfvars/terraform.tfvars" -auto-approve

DESTROY_EXIT=$?

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

if [ $DESTROY_EXIT -ne 0 ]; then
    echo "❌ terraform destroy falhou (código $DESTROY_EXIT)"
    echo "   O RDS foi parado e está seguro, mas revise os erros acima."
    exit 1
fi

# =============================================================================
# STEP 7: Instruções para restart manual do RDS
# =============================================================================
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  ✅ Rollback concluído!"
echo ""
echo "  📌 O RDS PostgreSQL foi PRESERVADO (parado, não destruído)."
echo "  📌 Snapshot salvo em: $(cat "$SNAPSHOT_FILE" 2>/dev/null || echo 'N/A')"
echo ""
echo "  ▶️  Para REINICIAR o RDS quando precisar:"
echo "     aws rds start-db-instance --db-instance-identifier $RDS_IDENTIFIER"
echo "     aws rds start-db-instance --db-instance-identifier $REPLICA_IDENTIFIER"
echo ""
echo "  ▶️  Para reimportar o RDS ao estado do Terraform (se for aplicar novamente):"
while read -r ADDR; do
    echo "     terraform import -var-file=tfvars/terraform.tfvars \"$ADDR\" \"<resource-id>\""
done < "$RDS_STATE_FILE"
echo ""
echo "═══════════════════════════════════════════════════════════════"

# Salva os endereços de state para referência futura
echo ""
echo "   Os endereços de state do RDS foram salvos em: $RDS_STATE_FILE"
echo ""
