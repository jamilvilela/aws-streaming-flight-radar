#!/bin/bash
# setup-env.sh - Load environment variables, deploy Terraform, then
# verify every resource the stack is supposed to create and dump the
# outputs the project needs to plug the notebook into the edge API.
#
# Usage:   ./setup-env.sh
# Aliases: ./setup-env.sh --skip-apply   # init/validate/plan only
#          ./setup-env.sh --no-verify    # skip post-deploy checks
#
# Exit codes:
#   0  success
#   1  prerequisites missing (env, tfvars, credentials)
#   2  terraform step failed
#   3  post-deploy verification found missing resources

set -a  # export everything we `source`

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# CLI flags
# ---------------------------------------------------------------------------
SKIP_APPLY=0
NO_VERIFY=0
for arg in "$@"; do
  case "$arg" in
    --skip-apply) SKIP_APPLY=1 ;;
    --no-verify)  NO_VERIFY=1 ;;
    -h|--help)
      sed -n '2,14p' "$0"
      exit 0
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
section() { echo -e "\n${BOLD}${BLUE}== $* ==${NC}"; }
ok()      { echo -e "  ${GREEN}✅ $*${NC}"; }
warn()    { echo -e "  ${YELLOW}⚠️  $*${NC}"; }
fail()    { echo -e "  ${RED}❌ $*${NC}"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { fail "Comando obrigatório ausente: $1"; exit 1; }
}

# ---------------------------------------------------------------------------
# STEP 1: Load .env
# ---------------------------------------------------------------------------
section "STEP 1 — Carregando .env"

if [ ! -f .env ]; then
  fail "Arquivo .env não encontrado na raiz do projeto."
  echo "   Copie .env.example para .env e preencha com seus valores"
  echo "   cp .env.example .env"
  exit 1
fi
source .env
ok "Variáveis de .env carregadas"

if [ -n "$AWS_REGION" ]; then
  export TF_VAR_region="$AWS_REGION"
fi

if [ -n "$RDS_ADMIN_PASSWORD" ]; then
  export TF_VAR_rds_admin_password="$RDS_ADMIN_PASSWORD"
  ok "RDS_ADMIN_PASSWORD carregada do .env (sobrescreve tfvars)"
fi

# ---------------------------------------------------------------------------
# STEP 2: AWS credentials sanity check (warn only, do not block)
# ---------------------------------------------------------------------------
section "STEP 2 — Verificando credenciais AWS"

CREDENTIALS_FOUND=0

# Check 1: environment variables
if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
  CREDENTIALS_FOUND=1
  ok "Credenciais AWS via environment variables"
fi

# Check 2: aws configure (default profile)
if [ "$CREDENTIALS_FOUND" -eq 0 ] && [ -f "$HOME/.aws/credentials" ]; then
  if grep -q "aws_access_key_id" "$HOME/.aws/credentials" 2>/dev/null; then
    CREDENTIALS_FOUND=1
    ok "Credenciais AWS via aws configure (default profile)"
  fi
fi

# Check 3: try sts get-caller-identity (covers SSO, instance profile, etc.)
if [ "$CREDENTIALS_FOUND" -eq 0 ]; then
  if aws sts get-caller-identity &>/dev/null; then
    CREDENTIALS_FOUND=1
    ok "Credenciais AWS ativas (SSO / instance profile / environment)"
  fi
fi

if [ "$CREDENTIALS_FOUND" -eq 0 ]; then
  warn "Nenhuma credencial AWS encontrada."
  echo "   Configure com 'aws configure', exporte AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY,"
  echo "   ou use uma role/SSO via 'aws sso login'."
  echo "   Continuando (pode falhar no terraform apply se não houver credenciais)."
fi

# ---------------------------------------------------------------------------
# STEP 3: Build the Lambda Layer (app/layers/python) — apenas se houver mudanças
# ---------------------------------------------------------------------------
section "STEP 3 — Construindo dependências da Lambda Layer"

PYTHON_BIN="${PYTHON_BIN:-python3}"
LAYER_ROOT_DIR="app/layers"
LAYER_SITEPACKAGES_DIR="$LAYER_ROOT_DIR/python"
REQ_FILE="app/requirements.txt"
CHECKSUM_FILE="$LAYER_ROOT_DIR/.layer-checksum"

if [ ! -f "$REQ_FILE" ]; then
  fail "Arquivo de requirements não encontrado em '$REQ_FILE'"
  exit 1
fi

# Compute checksum of requirements.txt (cross-platform: sha256sum, shasum, or Windows certutil)
hash_requirements() {
  if command -v sha256sum &>/dev/null; then
    sha256sum "$REQ_FILE" 2>/dev/null | cut -d' ' -f1
  elif command -v shasum &>/dev/null; then
    shasum -a 256 "$REQ_FILE" 2>/dev/null | cut -d' ' -f1
  else
    # Windows fallback: certutil -hashfile
    certutil -hashfile "$REQ_FILE" SHA256 2>/dev/null | findstr /r "^[0-9a-fA-F]" | tr -d ' \r\n'
  fi
}

mkdir -p "$LAYER_SITEPACKAGES_DIR"
CURRENT_HASH=$(hash_requirements)
STORED_HASH=""
[ -f "$CHECKSUM_FILE" ] && STORED_HASH=$(cat "$CHECKSUM_FILE")

if [ "$CURRENT_HASH" = "$STORED_HASH" ] && [ -d "$LAYER_SITEPACKAGES_DIR" ] && [ -n "$(ls -A "$LAYER_SITEPACKAGES_DIR" 2>/dev/null)" ]; then
  ok "Layer inalterada (checksum ok). Pulando instalação."
else
  echo -e "  ${BLUE}🧹 Limpando dependências anteriores...${NC}"
  rm -rf "$LAYER_SITEPACKAGES_DIR"/* 2>/dev/null || true
  rm -rf "$LAYER_SITEPACKAGES_DIR"/.[!.]* 2>/dev/null || true

  pushd "$LAYER_ROOT_DIR" >/dev/null 2>&1
  echo -e "  ${BLUE}📥 Instalando dependências de '$REQ_FILE'...${NC}"
  "$PYTHON_BIN" -m pip install \
    --platform manylinux2014_x86_64 \
    --implementation cp \
    --python-version 3.12 \
    --only-binary=:all: \
    -r ../requirements.txt \
    -t python
  popd >/dev/null 2>&1

  # Save checksum
  echo "$CURRENT_HASH" > "$CHECKSUM_FILE"
  ok "Layer atualizada em '$LAYER_SITEPACKAGES_DIR'"
fi

# ---------------------------------------------------------------------------
# STEP 4: Move into infra/
# ---------------------------------------------------------------------------
section "STEP 4 — Acessando diretório infra/"

if [ ! -d "infra" ]; then
  fail "Diretório infra/ não encontrado. Execute este script da raiz do projeto."
  exit 1
fi
cd infra || exit 1
ok "Diretório atual: $(pwd)"

set +a  # done auto-exporting

TFVARS_FILE="tfvars/terraform.tfvars"
if [ ! -f "$TFVARS_FILE" ]; then
  fail "Arquivo de variáveis '$TFVARS_FILE' não encontrado."
  echo "   Crie a partir do template: cp tfvars/terraform.tfvars.example tfvars/terraform.tfvars"
  exit 1
fi

# ---------------------------------------------------------------------------
# STEP 5-8: Terraform init/validate/plan/apply
# ---------------------------------------------------------------------------
section "STEP 5 — terraform init"
terraform init
[ $? -ne 0 ] && { fail "terraform init falhou"; exit 2; }
ok "init concluído"

section "STEP 6 — terraform validate"
terraform validate
[ $? -ne 0 ] && { fail "terraform validate falhou"; exit 2; }
ok "validate concluído"

section "STEP 7 — terraform plan"
terraform plan -var-file="$TFVARS_FILE" -out=tfplan
[ $? -ne 0 ] && { fail "terraform plan falhou"; exit 2; }
ok "plan concluido (salvo em tfplan)"

if [ "$SKIP_APPLY" -eq 1 ]; then
  warn "--skip-apply informado; apply nao sera executado."
else
  # -------------------------------------------------------------------------
  # STEP 7.5 — Ensure DMS secret exists (data source, not managed by TF)
  # -------------------------------------------------------------------------
  PROJECT_NAME="${PROJECT_NAME:-${TF_VAR_project_name:-$(grep -E '^project_name' "$TFVARS_FILE" | head -1 | cut -d= -f2 | tr -d ' \"')}}"
  PROJECT_NAME="${PROJECT_NAME//$'\r'}"
  DMS_SECRET_NAME="${PROJECT_NAME}-dms-aurora-credentials"

  if ! aws secretsmanager describe-secret --secret-id "$DMS_SECRET_NAME" --region "$AWS_REGION" &>/dev/null; then
    echo -e "  ${BLUE}Criando secret $DMS_SECRET_NAME...${NC}"
    aws secretsmanager create-secret \
      --name "$DMS_SECRET_NAME" \
      --description "RDS PostgreSQL credentials for DMS source endpoint (created by setup-env.sh)" \
      --secret-string '{"username":"placeholder","password":"placeholder"}' \
      --region "$AWS_REGION" > /dev/null
    ok "Secret $DMS_SECRET_NAME criado"
  else
    # Se existir mas estiver agendado para delecao, restaura
    DELETION_DATE=$(aws secretsmanager describe-secret \
      --secret-id "$DMS_SECRET_NAME" \
      --query 'DeletedDate' --output text --region "$AWS_REGION" 2>/dev/null)
    if [ -n "$DELETION_DATE" ] && [ "$DELETION_DATE" != "None" ]; then
      echo -e "  ${BLUE}Restaurando secret $DMS_SECRET_NAME (agendado para delecao)...${NC}"
      aws secretsmanager restore-secret \
        --secret-id "$DMS_SECRET_NAME" \
        --region "$AWS_REGION" > /dev/null
      ok "Secret restaurado"
    else
      ok "Secret $DMS_SECRET_NAME ja existe"
    fi
  fi

  section "STEP 8 — terraform apply"
  terraform apply -var-file="$TFVARS_FILE" -auto-approve tfplan
  [ $? -ne 0 ] && { fail "terraform apply falhou"; exit 2; }
  ok "apply concluido"

  # Populate DMS Secrets Manager secret with Aurora credentials
  if [ -n "${RDS_ADMIN_PASSWORD:-}" ]; then
    AURORA_USER="$(terraform output -raw aurora_admin_username 2>/dev/null || echo "dbadmin")"
    AURORA_ENDPOINT="$(terraform output -raw aurora_endpoint 2>/dev/null || echo "")"
    AURORA_PORT="$(terraform output -raw aurora_port 2>/dev/null || echo "5432")"
    AURORA_DBNAME="$(terraform output -raw aurora_db_name 2>/dev/null || echo "flightradar")"
    DMS_SECRET_VALUE="{\"username\":\"${AURORA_USER}\",\"password\":\"${RDS_ADMIN_PASSWORD}\",\"host\":\"${AURORA_ENDPOINT}\",\"port\":${AURORA_PORT},\"dbname\":\"${AURORA_DBNAME}\"}"
    aws secretsmanager put-secret-value \
      --secret-id "$DMS_SECRET_NAME" \
      --secret-string "$DMS_SECRET_VALUE" \
      --region "$AWS_REGION" &>/dev/null
    ok "DMS secret '$DMS_SECRET_NAME' populated with Aurora credentials (host/port/dbname included)"
  else
    warn "RDS_ADMIN_PASSWORD nao definido no .env. Nao foi possivel popular o secret do DMS."
  fi

fi

# ---------------------------------------------------------------------------
# STEP 9: Show all Terraform outputs
# ---------------------------------------------------------------------------
section "STEP 9 — Outputs do Terraform"

require_cmd terraform

# Helper: print a single output, falling back to a placeholder when missing.
print_output() {
  local name="$1"
  local sensitive="${2:-false}"

  # Try -raw first (simple string outputs)
  local value
  if value="$(terraform output -raw "$name" 2>/dev/null)" && [ -n "$value" ]; then
    if [ "$sensitive" = "true" ]; then
      echo -e "  ${BOLD}${name}${NC} = ${YELLOW}${value}${NC} ${RED}(sensitive)${NC}"
    else
      echo -e "  ${BOLD}${name}${NC} = ${value}"
    fi
    return
  fi

  # Fallback to -json for complex outputs (maps, lists, objects)
  if value="$(terraform output -json "$name" 2>/dev/null)" && [ -n "$value" ] && [ "$value" != "null" ]; then
    # Pretty-print with jq if available, otherwise show raw JSON
    if command -v jq &>/dev/null; then
      echo -e "  ${BOLD}${name}${NC} ="
      echo "$value" | jq -r 'to_entries[] | "    \(.key): \(.value | tostring)"' 2>/dev/null || \
      echo "$value" | jq -r '. | tostring' 2>/dev/null || \
      echo "$value"
    else
      echo -e "  ${BOLD}${name}${NC} = ${value}"
    fi
    return
  fi

  warn "Output '${name}' ausente"
}

echo -e "  ${BLUE}-- Edge API (use these in the notebook .env) --${NC}"
print_output api_invoke_url
print_output api_id
print_output api_key_id
print_output api_key_value true

echo ""
echo -e "  ${BLUE}-- Lambda --${NC}"
print_output lambda_flights_function_name
print_output lambda_flights_function_arn
print_output lambda_flights_iam_role_arn

echo ""
echo -e "  ${BLUE}-- Kinesis --${NC}"
print_output kinesis_stream_flights_info

echo ""
echo -e "  ${BLUE}-- DLQ --${NC}"
print_output flights_dlq_arn
print_output flights_dlq_url

echo ""
echo -e "  ${BLUE}-- Aurora Serverless v2 --${NC}"
print_output aurora_endpoint
print_output aurora_reader_endpoint
print_output aurora_port
print_output aurora_db_name
print_output aurora_admin_username true
print_output aurora_security_group_id
print_output aurora_connection true

echo ""
echo -e "  ${BLUE}-- DMS Serverless --${NC}"
print_output dms_replication_config_id
print_output dms_replication_config_arn
print_output dms_source_endpoint_arn
print_output dms_target_endpoint_arn
print_output dms_replication_config_identifier
print_output dms_security_group_id

# ---------------------------------------------------------------------------
# STEP 10: Post-deploy verification
# ---------------------------------------------------------------------------
if [ "$NO_VERIFY" -eq 1 ]; then
  warn "--no-verify informado; pulando checagens pós-deploy."
  exit 0
fi

section "STEP 10 — Verificação pós-deployment"

require_cmd aws
require_cmd jq

REGION="${AWS_REGION:-us-east-1}"
PROJECT_NAME="${TF_VAR_project_name:-$(grep -E '^project_name' "$TFVARS_FILE" | head -1 | cut -d= -f2 | tr -d ' \"')}"
PROJECT_NAME="${PROJECT_NAME//$'\r'}"
if [ -z "$PROJECT_NAME" ]; then
  fail "Não foi possível determinar project_name; defina TF_VAR_project_name ou edite o tfvars"
  exit 3
fi
ok "Projeto detectado: $PROJECT_NAME (region: $REGION)"

# ---------------------------------------------------------------------------
# 10.1 Kinesis streams
# ---------------------------------------------------------------------------
section "10.1 — Kinesis Data Streams"
STREAMS=$(aws kinesis list-streams --region "$REGION" --query 'StreamNames' --output json 2>/dev/null || echo "[]")
PROJECT_STREAMS=$(echo "$STREAMS" | jq --arg p "$PROJECT_NAME" -r '.[] | select(test("flight-radar|flights"))')
if [ -z "$PROJECT_STREAMS" ]; then
  fail "Nenhum Kinesis stream do projeto encontrado (esperado: contem 'flight-radar' ou 'flights')"
  echo "   Streams disponíveis:"
  echo "$STREAMS" | jq -r '.[] | "   - " + .'
  MISSING=1
else
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    STATUS=$(aws kinesis describe-stream-summary --stream-name "$s" --region "$REGION" \
      --query 'StreamDescriptionSummary.StreamStatus' --output text 2>/dev/null)
    ok "Stream '$s' (status: ${STATUS:-unknown})"
  done <<< "$PROJECT_STREAMS"
fi

# ---------------------------------------------------------------------------
# 10.2 Lambda functions
# ---------------------------------------------------------------------------
section "10.2 — Lambda Functions"
LAMBDAS=$(aws lambda list-functions --region "$REGION" --query 'Functions[].FunctionName' --output json 2>/dev/null || echo "[]")
PROJECT_LAMBDAS=$(echo "$LAMBDAS" | jq --arg p "$PROJECT_NAME" -r '.[] | select(startswith($p))')
if [ -z "$PROJECT_LAMBDAS" ]; then
  fail "Nenhuma Lambda do projeto encontrada (prefixo esperado: $PROJECT_NAME)"
  MISSING=1
else
  while IFS= read -r fn; do
    [ -z "$fn" ] && continue
    STATE=$(aws lambda get-function --function-name "$fn" --region "$REGION" \
      --query 'Configuration.State' --output text 2>/dev/null)
    RUNTIME=$(aws lambda get-function --function-name "$fn" --region "$REGION" \
      --query 'Configuration.Runtime' --output text 2>/dev/null)
    ok "Lambda '$fn' (runtime: $RUNTIME, state: ${STATE:-unknown})"
  done <<< "$PROJECT_LAMBDAS"
fi

# ---------------------------------------------------------------------------
# 10.3 IAM roles for the lambdas
# ---------------------------------------------------------------------------
section "10.3 — IAM Roles"
if [ -n "$PROJECT_LAMBDAS" ]; then
  while IFS= read -r fn; do
    [ -z "$fn" ] && continue
    ROLE_ARN=$(aws lambda get-function --function-name "$fn" --region "$REGION" \
      --query 'Configuration.Role' --output text 2>/dev/null)
    ROLE_NAME=$(echo "$ROLE_ARN" | awk -F'/' '{print $NF}')
    if [ -n "$ROLE_NAME" ]; then
      TRUST=$(aws iam get-role --role-name "$ROLE_NAME" \
        --query 'Role.AssumeRolePolicyDocument.Statement[0].Principal.Service' --output text 2>/dev/null)
      ok "Role '$ROLE_NAME' (assume: ${TRUST:-unknown})"
    fi
  done <<< "$PROJECT_LAMBDAS"
fi

# ---------------------------------------------------------------------------
# 10.4 SQS DLQ
# ---------------------------------------------------------------------------
section "10.4 — SQS Dead Letter Queues"
QUEUES=$(aws sqs list-queues --region "$REGION" --query 'QueueUrls' --output json 2>/dev/null || echo "[]")
DLQ_URLS=$(echo "$QUEUES" | jq --arg p "$PROJECT_NAME" -r '.[] | select(test($p + ".*flights-dlq"))')
if [ -z "$DLQ_URLS" ]; then
  fail "DLQ do projeto não encontrada (esperado: ${PROJECT_NAME}*flights-dlq)"
  MISSING=1
else
  while IFS= read -r url; do
    [ -z "$url" ] && continue
    ok "DLQ: $url"
  done <<< "$DLQ_URLS"
fi

# ---------------------------------------------------------------------------
# 10.5 API Gateway
# ---------------------------------------------------------------------------
section "10.5 — API Gateway (REST API)"
APIS=$(aws apigateway get-rest-apis --region "$REGION" \
  --query 'items[].[id,name]' --output json 2>/dev/null || echo "[]")
PROJECT_APIS=$(echo "$APIS" | jq --arg p "$PROJECT_NAME" -r '.[] | select(.[1] | test($p)) | @tsv')
if [ -z "$PROJECT_APIS" ]; then
  fail "API Gateway do projeto não encontrado (nome esperado contém: $PROJECT_NAME)"
  MISSING=1
else
  while IFS=$'\t' read -r api_id api_name; do
    [ -z "$api_id" ] && continue
    ok "API '$api_name' (id: $api_id)"

    # Stages
    STAGES=$(aws apigateway get-stages --rest-api-id "$api_id" --region "$REGION" \
      --query 'item[].stageName' --output json 2>/dev/null || echo "[]")
    while IFS= read -r stage; do
      [ -z "$stage" ] && continue
      INVOKE_URL="https://${api_id}.execute-api.${REGION}.amazonaws.com/${stage}"
      ok "  Stage: $stage  →  ${INVOKE_URL}"
    done < <(echo "$STAGES" | jq -r '.[]')

    # API keys
    KEYS=$(aws apigateway get-api-keys --rest-api-id "$api_id" --region "$REGION" \
      --query 'items[].[id,name,enabled]' --output json 2>/dev/null || echo "[]")
    while IFS=$'\t' read -r kid kname kenabled; do
      [ -z "$kid" ] && continue
      key_value=$(aws apigateway get-api-key --api-key "$kid" --include-value \
        --region "$REGION" --query 'value' --output text 2>/dev/null)
      ok "  API Key: $kname (id: $kid, enabled: $kenabled, value: ${key_value:0:8}...)"
    done < <(echo "$KEYS" | jq -r '.[] | @tsv')

    # Usage plan
    PLANS=$(aws apigateway get-usage-plans --region "$REGION" \
      --query 'items[].[id,name,throttle.rateLimit,throttle.burstLimit,quota.limit,quota.period]' \
      --output json 2>/dev/null || echo "[]")
    while IFS=$'\t' read -r pid pname p_rate p_burst p_quota p_period; do
      [ -z "$pid" ] && continue
      ok "  Usage Plan: $pname (rate=${p_rate}/s, burst=${p_burst}, quota=${p_quota:-none}/${p_period:-none})"
    done < <(echo "$PLANS" | jq -r '.[] | @tsv')
  done <<< "$PROJECT_APIS"
fi

# ---------------------------------------------------------------------------
# 10.6 CloudWatch Log Groups
# ---------------------------------------------------------------------------
section "10.6 — CloudWatch Log Groups"
LOG_GROUPS=$(aws logs describe-log-groups --region "$REGION" \
  --log-group-name-prefix "/aws/lambda/${PROJECT_NAME}" \
  --query 'logGroups[].logGroupName' --output json 2>/dev/null || echo "[]")
LAMBDA_LG_COUNT=$(echo "$LOG_GROUPS" | jq 'length')
if [ "$LAMBDA_LG_COUNT" -gt 0 ]; then
  ok "$LAMBDA_LG_COUNT Lambda log group(s):"
  echo "$LOG_GROUPS" | jq -r '.[] | "   - " + .'
else
  warn "Nenhum log group /aws/lambda/${PROJECT_NAME}* encontrado"
fi

APIGW_LG=$(aws logs describe-log-groups --region "$REGION" \
  --log-group-name-prefix "/aws/apigateway/${PROJECT_NAME}" \
  --query 'logGroups[].logGroupName' --output json 2>/dev/null || echo "[]")
APIGW_LG_COUNT=$(echo "$APIGW_LG" | jq 'length')
if [ "$APIGW_LG_COUNT" -gt 0 ]; then
  ok "$APIGW_LG_COUNT API Gateway log group(s):"
  echo "$APIGW_LG" | jq -r '.[] | "   - " + .'
fi

# ---------------------------------------------------------------------------
# 10.7 DMS Serverless
# ---------------------------------------------------------------------------
section "10.7 — DMS Serverless"
DMS_CONFIGS=$(aws dms describe-replication-configs --region "$REGION" \
  --query "ReplicationConfigs[?contains(ReplicationConfigIdentifier, \`${PROJECT_NAME}\`)].{ID:ReplicationConfigIdentifier,Status:Status}" \
  --output json 2>/dev/null || echo "[]")
DMS_CONFIG_COUNT=$(echo "$DMS_CONFIGS" | jq 'length')
if [ "$DMS_CONFIG_COUNT" -gt 0 ]; then
  ok "$DMS_CONFIG_COUNT DMS Serverless config(s):"
  echo "$DMS_CONFIGS" | jq -r '.[] | "   - \(.ID) (status: \(.Status))"'
else
  warn "Nenhuma DMS Serverless config do projeto encontrada"
fi

# ---------------------------------------------------------------------------
# 10.8 KMS keys
# ---------------------------------------------------------------------------
section "10.8 — KMS Keys"
KMS_KEYS=$(aws kms list-aliases --region "$REGION" \
  --query 'Aliases[?contains(AliasName, `'"$PROJECT_NAME"'`)].AliasName' \
  --output json 2>/dev/null || echo "[]")
KMS_COUNT=$(echo "$KMS_KEYS" | jq 'length')
if [ "$KMS_COUNT" -gt 0 ]; then
  ok "$KMS_COUNT KMS alias(es):"
  echo "$KMS_KEYS" | jq -r '.[] | "   - " + .'
else
  warn "Nenhum alias KMS do projeto encontrado (pode ser intencional)"
fi

# ---------------------------------------------------------------------------
# STEP 11: Final summary
# ---------------------------------------------------------------------------
section "STEP 11 — Resumo final"

API_URL=$(terraform output -raw api_invoke_url 2>/dev/null || echo "<missing>")
API_KEY=$(terraform output -raw api_key_value 2>/dev/null || echo "<missing>")
NOTEBOOK_ENV="app/get_flights_data/src/.env"

echo ""
echo -e "${BOLD}URLs e credenciais para o notebook:${NC}"
echo -e "  ${BOLD}API_BASE_URL${NC} = ${GREEN}${API_URL}${NC}"
echo -e "  ${BOLD}API_KEY${NC}      = ${YELLOW}${API_KEY}${NC}"
echo ""
echo -e "Atualize ${BOLD}${NOTEBOOK_ENV}${NC} com:"
echo "  API_BASE_URL='${API_URL}'"
echo "  API_KEY='${API_KEY}'"
echo ""

if [ "${MISSING:-0}" = "1" ]; then
  fail "Verificação pós-deployment encontrou recursos faltando (ver acima)."
  echo ""
  echo -e "${BOLD}Próximos passos (mesmo com falhas):${NC}"
  echo "  1. Revise 'terraform plan' / 'terraform apply' acima"
  echo "  2. aws logs tail /aws/lambda/${PROJECT_NAME}-flights-raw --follow --region $REGION"
  echo "  3. Teste o endpoint:  curl -X POST \"\${API_URL}/flights\" -H \"X-Api-Key: \${API_KEY}\" \\"
  echo "                          -H 'Content-Type: application/json' \\"
  echo "                          -d '{\"icao24\":\"abc123\"}'"
  exit 3
fi

echo -e "${GREEN}${BOLD}🎉 Deployment concluído e verificado com sucesso!${NC}"
echo ""
echo -e "${BOLD}Próximos passos:${NC}"
echo "  1. Cole API_BASE_URL e API_KEY em ${NOTEBOOK_ENV}"
echo "  2. Reinicie o kernel do notebook e rode a cell 'smoke-test-api'"
echo "  3. Smoke test do endpoint:"
echo "     curl -X POST \"${API_URL}/flights\" \\"
echo "          -H \"X-Api-Key: ${API_KEY}\" \\"
echo "          -H 'Content-Type: application/json' \\"
echo "          -d '{\"icao24\":\"abc123\",\"callsign\":\"TEST01\",\"latitude\":-23.5,\"longitude\":-46.6}'"
echo "  4. Logs:"
echo "     aws logs tail /aws/lambda/${PROJECT_NAME}-flights-raw --follow --region $REGION"
echo ""
exit 0
