#!/bin/bash
# restore-from-snapshot.sh - Recreate RDS from a saved snapshot
# Usage:
#   ./scripts/rds/restore-from-snapshot.sh              # uses last snapshot saved by rollback-setup.sh
#   ./scripts/rds/restore-from-snapshot.sh <snapshot-id> # uses a specific snapshot
#
# Workflow:
#   1. Set TF_VAR_rds_snapshot_identifier to the snapshot ID
#   2. Run terraform apply to recreate RDS (restored from snapshot)
#   3. After apply, clear the variable so future applies don't reference it

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INFRA_DIR="$PROJECT_ROOT/infra"
SNAPSHOT_FILE=".rds-snapshot-id"

# Determine snapshot ID
if [ $# -ge 1 ]; then
    SNAPSHOT_ID="$1"
    echo "📌 Usando snapshot informado: $SNAPSHOT_ID"
elif [ -f "$INFRA_DIR/$SNAPSHOT_FILE" ]; then
    SNAPSHOT_ID=$(cat "$INFRA_DIR/$SNAPSHOT_FILE")
    echo "📌 Usando snapshot salvo: $SNAPSHOT_ID"
else
    echo "❌ Nenhum snapshot especificado."
    echo "   Uso: $0 [snapshot-id]"
    echo "   Ou execute primeiro: ./rollback-setup.sh (que salva o snapshot em infra/$SNAPSHOT_FILE)"
    exit 1
fi

# Verify snapshot exists
echo "🔍 Verificando snapshot $SNAPSHOT_ID..."
if ! aws rds describe-db-snapshots --db-snapshot-identifier "$SNAPSHOT_ID" &>/dev/null; then
    echo "❌ Snapshot $SNAPSHOT_ID não encontrado na conta AWS."
    exit 1
fi

echo "✅ Snapshot encontrado. Status: $(aws rds describe-db-snapshots --db-snapshot-identifier "$SNAPSHOT_ID" --query 'DBSnapshots[0].Status' --output text)"
echo ""
echo "⚠️  Este script irá:"
echo "   1. Exportar TF_VAR_rds_snapshot_identifier=\"$SNAPSHOT_ID\""
echo "   2. Executar terraform apply em $INFRA_DIR"
echo "   3. Remover o arquivo $SNAPSHOT_FILE (já que o snapshot foi usado)"
echo ""

# echo "Digite 'sim' para continuar:"
# read -r CONFIRM
# if [ "$CONFIRM" != "sim" ]; then
#     echo "❌ Cancelado."
#     exit 0
# fi

export TF_VAR_rds_snapshot_identifier="$SNAPSHOT_ID"
# Terraform variable: rds_snapshot_identifier (root-level)
# Used in main.tf to override rds_config.snapshot_identifier when set

cd "$INFRA_DIR" || exit 1

echo ""
echo "🚀 Executando terraform apply para restaurar RDS do snapshot..."
echo "   (O RDS será criado a partir do snapshot, preservando todos os dados)"
echo ""

terraform apply -var-file="tfvars/terraform.tfvars"

# Cleanup snapshot file after successful apply
if [ -f "$SNAPSHOT_FILE" ]; then
    rm "$SNAPSHOT_FILE"
    echo "🗑️  Arquivo $SNAPSHOT_FILE removido."
fi

echo ""
echo "✅ RDS restaurado do snapshot $SNAPSHOT_ID!"
echo "   Connection: $(terraform output -raw rds_psql_connection 2>/dev/null || echo 'verifique os outputs')"
echo ""
echo "⚠️  IMPORTANTE: Remova snapshot_identifier do rds_config nos .tfvars"
echo "   ou defina como null para evitar conflitos em próximos applies."
echo "   Execute: terraform apply -var-file=\"tfvars/terraform.tfvars\""
