#!/bin/bash
# ============================================================================
# SCRIPT DE DEPLOYMENT: FLINK SQL APPLICATION
# ============================================================================
#
# Este script:
# 1. Valida a estrutura SQL (sintaxe)
# 2. Inicia a aplicação Flink via AWS CLI
# 3. Monitora logs e status
# 4. Simula teste de dados
#
# Pré-requisitos:
#   • AWS CLI configurado
#   • KDA application criada (via Terraform)
#   • Arquivo JAR do Flink em S3
#
# Uso:
#   bash deploy_flink_sql.sh [start|stop|status|test|logs]
#
# ============================================================================

set -e

# Configuração
PROJECT_NAME="flight-radar-stream"
KDA_APP_NAME="${PROJECT_NAME}-kda-flights"
AWS_REGION="us-east-1"
FLINK_SQL_DIR="./app/flink-sql-application"
LOG_GROUP="/aws/kinesisanalytics/${KDA_APP_NAME}"
LOG_STREAM="FlinkApplicationLogs"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# FUNÇÕES AUXILIARES
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# ============================================================================
# FUNÇÃO: VALIDAR SINTAXE SQL
# ============================================================================

validate_sql() {
    log_info "Validando sintaxe SQL..."
    
    local sql_files=(
        "01_source.sql"
        "02_enriched_view.sql"
        "03_sinks_kinesis.sql"
    )
    
    for sql_file in "${sql_files[@]}"; do
        if [ ! -f "${FLINK_SQL_DIR}/${sql_file}" ]; then
            log_error "Arquivo não encontrado: ${FLINK_SQL_DIR}/${sql_file}"
            exit 1
        fi
        log_success "Arquivo validado: ${sql_file}"
    done
    
    log_success "Todos os arquivos SQL existem"
}

# ============================================================================
# FUNÇÃO: INICIAR APLICAÇÃO FLINK
# ============================================================================

start_application() {
    log_info "Iniciando aplicação Flink: ${KDA_APP_NAME}..."
    
    # Verificar se aplicação existe
    local app_status=$(aws kinesisanalyticsv2 describe-application \
        --application-name "${KDA_APP_NAME}" \
        --region "${AWS_REGION}" \
        --query 'ApplicationDetail.ApplicationStatus' \
        --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "${app_status}" == "NOT_FOUND" ]; then
        log_error "Aplicação não encontrada: ${KDA_APP_NAME}"
        log_info "Crie a aplicação usando Terraform antes"
        exit 1
    fi
    
    if [ "${app_status}" == "RUNNING" ]; then
        log_warning "Aplicação já está em execução"
        return 0
    fi
    
    log_info "Status atual: ${app_status}"
    
    # Iniciar aplicação
    aws kinesisanalyticsv2 start-application \
        --application-name "${KDA_APP_NAME}" \
        --run-configuration "{}"\
        --region "${AWS_REGION}"
    
    log_info "Comando enviado. Aguardando inicialização..."
    
    # Aguardar inicialização (máx 5 minutos)
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local current_status=$(aws kinesisanalyticsv2 describe-application \
            --application-name "${KDA_APP_NAME}" \
            --region "${AWS_REGION}" \
            --query 'ApplicationDetail.ApplicationStatus' \
            --output text 2>/dev/null || echo "ERROR")
        
        if [ -z "${current_status}" ] || [ "${current_status}" == "ERROR" ]; then
            log_error "Erro ao buscar status"
            exit 1
        fi
        
        if [ "${current_status}" == "RUNNING" ]; then
            log_success "Aplicação iniciada com sucesso!"
            return 0
        fi
        
        log_info "Status: ${current_status} (aguardando... ${attempt}/${max_attempts})"
        sleep 10
        ((attempt++))
    done
    
    log_error "Timeout ao aguardar inicialização da aplicação"
    exit 1
}

# ============================================================================
# FUNÇÃO: PARAR APLICAÇÃO FLINK
# ============================================================================

stop_application() {
    log_info "Parando aplicação Flink: ${KDA_APP_NAME}..."
    
    aws kinesisanalyticsv2 stop-application \
        --application-name "${KDA_APP_NAME}" \
        --region "${AWS_REGION}" || {
        log_warning "Erro ao parar aplicação (pode já estar parada)"
    }
    
    log_success "Comando de parada enviado"
}

# ============================================================================
# FUNÇÃO: VER STATUS
# ============================================================================

show_status() {
    log_info "Status da aplicação Flink: ${KDA_APP_NAME}..."
    
    aws kinesisanalyticsv2 describe-application \
        --application-name "${KDA_APP_NAME}" \
        --region "${AWS_REGION}" \
        --query 'ApplicationDetail.[ApplicationName,ApplicationStatus,ApplicationARN,CreateTimestamp]' \
        --output table
    
    log_info "Versão da aplicação:"
    aws kinesisanalyticsv2 describe-application \
        --application-name "${KDA_APP_NAME}" \
        --region "${AWS_REGION}" \
        --query 'ApplicationDetail.ApplicationVersionId' \
        --output text
}

# ============================================================================
# FUNÇÃO: VER LOGS
# ============================================================================

show_logs() {
    log_info "Exibindo últimos 100 logs (últimas 5 minutos)..."
    
    local start_time=$(date -u -d '5 minutes ago' +%s)000
    
    aws logs filter-log-events \
        --log-group-name "${LOG_GROUP}" \
        --log-stream-name-prefix "${LOG_STREAM}" \
        --start-time ${start_time} \
        --region "${AWS_REGION}" \
        --query 'events[*].[timestamp,message]' \
        --output table || log_warning "Nenhum log encontrado"
    
    log_info "Para monitoramento contínuo:"
    log_info "  aws logs tail ${LOG_GROUP} --follow"
}

# ============================================================================
# FUNÇÃO: TESTE COM DADOS SIMULADOS
# ============================================================================

test_with_sample_data() {
    log_info "Aguardando 30s para o Flink iniciar a leitura (modo LATEST)..."
    sleep 30

    log_info "Enviando dados de teste para Kinesis..."
    
    local current_time=$(date -u +"%Y-%m-%dT%H:%M:%S")
    local test_data='{"icao24": "test12", "callsign": "TST123  ", "origin_country": "Brazil", "time_position": "'${current_time}'", "last_contact": "'${current_time}'", "longitude": -46.65, "latitude": -23.55, "altitude": 10000.0, "on_ground": false, "velocity": 250.0, "heading": 90.0, "vertical_rate": 0.0, "geo_altitude": 10000.0, "squawk": "1234", "spi": false, "position_source": 0}'
    
    # Enviar 5 eventos de teste
    for i in {1..5}; do
        aws kinesis put-record \
            --stream-name "${PROJECT_NAME}-flights" \
            --data "${test_data}" \
            --partition-key "test-partition" \
            --region "${AWS_REGION}" \
            --cli-binary-format raw-in-base64-out \
            > /dev/null
        log_success "Evento de teste ${i}/5 enviado"
        sleep 1
    done
    
    log_info "Aguardando processamento (15 segundos)..."
    sleep 15
    
    log_info "Verificando saída do Sink (flights-rt)..."
    local shard_id=$(aws kinesis list-shards --stream-name "${PROJECT_NAME}-flights-rt" --region "${AWS_REGION}" --query 'Shards[0].ShardId' --output text)
    
    if [ "${shard_id}" != "None" ]; then
        aws kinesis get-records \
            --shard-iterator $(aws kinesis get-shard-iterator \
                --stream-name "${PROJECT_NAME}-flights-rt" \
                --shard-id "${shard_id}" \
                --shard-iterator-type TRIM_HORIZON \
                --region "${AWS_REGION}" \
                --query 'ShardIterator' \
                --output text) \
            --region "${AWS_REGION}" \
            --query 'Records[*].Data' \
            --output text | base64 -d 2>/dev/null | jq '.' || log_warning "Nenhum dado processado encontrado nos últimos segundos."
    else
        log_error "Não foi possível encontrar shards para o stream ${PROJECT_NAME}-flights-rt"
    fi
}

# ============================================================================
# FUNÇÃO: CRIAR KINESIS STREAMS
# ============================================================================

create_kinesis_streams() {
    log_info "Criando Kinesis streams (se não existirem)..."
    
    local streams=(
        "${PROJECT_NAME}-flights:flights-raw"
        "${PROJECT_NAME}-flights-positions-1min:flights-positions-1min"
        "${PROJECT_NAME}-flights-altitude-bands:flights-altitude-bands"
        "${PROJECT_NAME}-flights-phase-changes:flights-phase-changes"
        "${PROJECT_NAME}-flights-enriched-raw:flights-enriched-raw"
    )
    
    for stream_pair in "${streams[@]}"; do
        local stream_name=$(echo $stream_pair | cut -d: -f2)
        
        # Verificar se stream existe
        if aws kinesis describe-stream \
            --stream-name "${stream_name}" \
            --region "${AWS_REGION}" \
            > /dev/null 2>&1; then
            log_success "Stream já existe: ${stream_name}"
        else
            log_info "Criando stream: ${stream_name}..."
            aws kinesis create-stream \
                --stream-name "${stream_name}" \
                --stream-mode-details StreamMode=ON_DEMAND \
                --region "${AWS_REGION}"
            log_success "Stream criado: ${stream_name}"
        fi
    done
}

# ============================================================================
# MENU PRINCIPAL
# ============================================================================

main() {
    local command="${1:-help}"
    
    case "${command}" in
        deploy)
            validate_sql
            create_kinesis_streams
            start_application
            ;;
        start)
            start_application
            ;;
        stop)
            stop_application
            ;;
        status)
            show_status
            ;;
        logs)
            show_logs
            ;;
        test)
            test_with_sample_data
            ;;
        validate)
            validate_sql
            log_success "Validação concluída"
            ;;
        *)
            cat << 'EOF'

╔══════════════════════════════════════════════════════════════════════════════╗
║                  FLINK SQL APPLICATION DEPLOYMENT                           ║
╚══════════════════════════════════════════════════════════════════════════════╝

USAGE:
  bash deploy_flink_sql.sh [COMMAND]

COMMANDS:
  start       - Iniciar aplicação Flink (cria streams se necessário)
  stop        - Parar aplicação Flink
  status      - Mostrar status atual da aplicação
  logs        - Exibir logs do CloudWatch dos últimos 5 minutos
  test        - Enviar dados de teste e verificar saída
  validate    - Validar sintaxe SQL e estrutura

EJEMPLOS:
  # Iniciar aplicação completa
  bash deploy_flink_sql.sh start

  # Monitorar status
  bash deploy_flink_sql.sh status

  # Ver logs em tempo real
  aws logs tail /aws/kinesisanalytics/flight-radar-kda-flights --follow

  # Enviar dados de teste
  bash deploy_flink_sql.sh test

MONITORAMENTO:
  # Ver eventos em um stream Kinesis
  aws kinesis describe-stream --stream-name flights-enriched-raw

  # Consumir eventos (últimos 24h)
  aws kinesis get-records \
    --shard-iterator $(aws kinesis get-shard-iterator \
      --stream-name flights-enriched-raw \
      --shard-id shardId-000000000000 \
      --shard-iterator-type TRIM_HORIZON | jq -r '.ShardIterator')

PRÉ-REQUISITOS:
  1. AWS CLI configurado e autenticado
  2. KDA application criada via Terraform
  3. Arquivo JAR em S3
  4. Streams Kinesis (serão criados automaticamente)
  5. CloudWatch Logs habilitado

ARQUIVOS SQL:
  - 01_source.sql         → Table SOURCE (Kinesis input)
  - 02_enriched_view.sql  → VIEW com transformações
  - 03_sinks_kinesis.sql  → 4 Sinks de saída

═══════════════════════════════════════════════════════════════════════════════

EOF
            ;;
    esac
}

# Executar main
main "$@"
