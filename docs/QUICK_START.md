# 🚀 Quick Reference: Deploy & Operations

## 📋 Antes de Começar

```bash
# 1. Clonar projeto
git clone https://github.com/your-org/aws-streaming-flight-radar
cd aws-streaming-flight-radar

# 2. Verificar estrutura
ls -la infra/modules/redshift_serverless/
# ✓ main.tf, variables.tf, outputs.tf, data.tf, ddl.sql

# 3. Verificar AWS credentials
aws sts get-caller-identity
```

---

## 🔑 Passo 1: Configurar Variáveis

**`infra/tfvars/terraform.tfvars`**:

```hcl
project_name = "flight-radar"
aws_region   = "us-east-1"
environment  = "dev"

redshift_config = {
  admin_username       = "admin"
  admin_password       = "SecurePassword123!@#"  # Mude isso!
  base_capacity        = 32      # RPUs
  max_capacity         = 256     # RPUs
  backup_retention_days = 7
  log_retention_days   = 7
}

flink_config = {
  parallelism = 1      # 4 KPUs
  auto_start  = false  # true em produção
}

# ... outras variáveis ...
```

---

## 🏗️ Passo 2: Deploy com Terraform

```bash
cd infra

# 1. Inicializar
terraform init

# 2. Planejar (dry-run)
terraform plan -out=tfplan

# 3. Aplicar
terraform apply tfplan

# 4. Verificar outputs
terraform output redshift_endpoint
terraform output redshift_connection_string
```

**Tempo esperado**: 5-10 minutos

---

## 🔗 Passo 3: Aplicar DDL Schema

```bash
# 1. Pegar endpoint
REDSHIFT_ENDPOINT=$(terraform output -raw workgroup_endpoint)

# 2. Conectar e executar DDL
psql \
  -h $REDSHIFT_ENDPOINT \
  -U admin \
  -d flightradar \
  -f modules/redshift_serverless/ddl.sql

# 3. Verificar tabelas criadas
psql \
  -h $REDSHIFT_ENDPOINT \
  -U admin \
  -d flightradar \
  -c "\dt flight_radar.*"
```

---

## 📢 Passo 4: Setup Alertas SNS

```bash
# Configuração interativa
bash scripts/setup_kda_alerts.sh

# Menu:
# 1) Setup Email subscription
# 2) List Subscriptions
# 3) Test Alarm Notification
# 4) Show Alarm Status
# 5) Exit

# Escolher opção 1, fornecer email
# Confirmar subscription no email
```

---

## ✅ Passo 5: Verificar Deploy

```bash
# Redshift status
aws redshiftserverless describe-workgroups \
  --query 'Workgroups[*].[WorkgroupName,WorkgroupStatus]'

# KDA status
aws kinesisanalyticsv2 describe-application \
  --application-name flight-radar-kda-flights \
  --query 'ApplicationDetail.ApplicationStatus'

# SNS topic
aws sns list-subscriptions-by-topic \
  --topic-arn $(terraform output -raw sns_topic_arn)

# CloudWatch alarms
aws cloudwatch describe-alarms \
  --alarm-name-prefix flight-radar-kda \
  --query 'MetricAlarms[*].[AlarmName,StateValue]'
```

---

## 🔍 Monitoramento

### Ver Logs KDA Flink

```bash
aws logs tail /aws/kinesisanalytics/flight-radar-kda-flights --follow
```

### Ver Logs Redshift

```bash
aws logs tail /aws/redshift-serverless/flight-radar --follow
```

### Dashboard CloudWatch

```bash
# Abrir no navegador
echo "https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=flight-radar-kda-flights"
```

---

## ⚡ Operações Comuns

### Iniciar KDA (Desenvolvimento)

```bash
bash app/flink-sql-application/deploy_flink_sql.sh start
```

### Parar KDA (Desenvolvimento)

```bash
bash app/flink-sql-application/deploy_flink_sql.sh stop
```

### Testar Pipeline de Dados

```bash
python scripts/test_flink_pipeline.py
```

### Conectar ao Redshift (SQL Query)

```bash
psql \
  -h $(terraform output -raw workgroup_endpoint) \
  -U admin \
  -d flightradar

# Dentro do psql:
SELECT COUNT(*) FROM flight_radar.state_vectors;
SELECT * FROM flight_radar.mv_active_aircraft_summary;
SELECT * FROM flight_radar.mv_top_countries LIMIT 10;
```

### Aumentar Capacidade Redshift

```hcl
# Em tfvars/terraform.tfvars:
redshift_config = {
  ...
  base_capacity = 64    # De 32 para 64
  max_capacity  = 512   # De 256 para 512
}

# Deploy
terraform apply
```

---

## 🚨 Troubleshooting Rápido

### KDA não está recebendo dados

```bash
# 1. Verificar Kinesis source
aws kinesis describe-stream --stream-name flights-raw

# 2. Verificar Lambda
aws lambda invoke \
  --function-name flight-radar-flights-raw \
  /tmp/response.json
cat /tmp/response.json

# 3. Verificar Flink logs
aws logs tail /aws/kinesisanalytics/flight-radar-kda-flights --follow
```

### Redshift vazio

```bash
# 1. Verificar se Redshift está acessível
psql -h <endpoint> -U admin -d flightradar -c "SELECT 1"

# 2. Verificar dados em Kinesis
aws kinesis get-shard-iterator \
  --stream-name enriched-raw \
  --shard-id shardId-000000000000 \
  --shard-iterator-type TRIM_HORIZON

# 3. Verificar estrutura de tabelas
psql -h <endpoint> -U admin -d flightradar -c "\d flight_radar.state_vectors"
```

### Alarmes não disparam

```bash
# 1. Testar SNS
aws sns publish \
  --topic-arn $(terraform output -raw sns_topic_arn) \
  --subject "Test Alert" \
  --message "This is a test notification"

# 2. Verificar subscriptions
aws sns list-subscriptions-by-topic \
  --topic-arn $(terraform output -raw sns_topic_arn)

# 3. Verificar alarme status
aws cloudwatch describe-alarms \
  --alarm-names flight-radar-kda-failed-checkpoints
```

---

## 🔐 Segurança

### Mudar Redshift Password

```bash
# Não recomendado via CLI - use AWS Console ou IaC

# Via Terraform:
# 1. Atualizar em tfvars/terraform.tfvars
# 2. terraform apply
# 3. Redshift notificará mudança
```

### Rotacionar IAM Credentials (CI/CD)

```bash
# Documented in: docs/GITHUB_ACTIONS_SETUP.md
# AWS OIDC automatic rotation every 1 hour
```

### Auditar Access

```bash
# Ver quem acessou Redshift
aws logs filter-log-events \
  --log-group-name /aws/redshift-serverless/flight-radar \
  --filter-pattern "CONNECTION"

# Ver falhas de conexão
aws logs filter-log-events \
  --log-group-name /aws/redshift-serverless/flight-radar \
  --filter-pattern "ERROR"
```

---

## 📊 Queries Úteis

### Quantos voos agora

```sql
SELECT COUNT(DISTINCT icao24) 
FROM flight_radar.state_vectors 
WHERE event_timestamp_utc > NOW() - INTERVAL '5 minutes';
```

### Top 10 países

```sql
SELECT 
  origin_country,
  COUNT(DISTINCT icao24) as aircraft_count
FROM flight_radar.state_vectors
WHERE event_timestamp_utc > NOW() - INTERVAL '1 hour'
GROUP BY origin_country
ORDER BY aircraft_count DESC
LIMIT 10;
```

### Aviões em subida

```sql
SELECT 
  icao24,
  callsign,
  altitude_ft,
  vertical_rate_fpm,
  flight_phase
FROM flight_radar.state_vectors
WHERE vertical_trend = 'CLIMBING'
  AND event_timestamp_utc > NOW() - INTERVAL '1 minute'
ORDER BY vertical_rate_fpm DESC;
```

### Dashboard summary

```sql
SELECT * FROM flight_radar.mv_active_aircraft_summary;
```

---

## 📁 Arquivos Importantes

| Arquivo | Propósito |
|---------|-----------|
| `infra/modules/redshift_serverless/` | Módulo Redshift |
| `infra/modules/redshift_serverless/ddl.sql` | Schema SQL |
| `infra/modules/kda_flights/` | Módulo KDA Flink |
| `scripts/setup_kda_alerts.sh` | Setup SNS |
| `app/flink-sql-application/` | SQL Flink scripts |
| `docs/ARCHITECTURE_INTEGRATED.md` | Documentação |
| `DELIVERY_SUMMARY.md` | Resumo da entrega |

---

## 🎯 Next Steps

- [ ] Configurar redshift_config no terraform.tfvars
- [ ] `terraform apply`
- [ ] Aplicar DDL SQL
- [ ] Setup SNS subscriptions
- [ ] Iniciar KDA
- [ ] Verificar dados em Redshift
- [ ] Conectar QuickSight
- [ ] Criar dashboards

---

## 📞 Referências

- 📖 [Redshift Module README](infra/modules/redshift_serverless/README.md)
- 📖 [Architecture Diagram](docs/ARCHITECTURE_INTEGRATED.md)
- 📖 [KDA Alarms Guide](docs/KDA_IAM_ALARMS_GUIDE.md)
- 📖 [Deployment Strategy](docs/DEPLOYMENT_STRATEGY.md)

---

**Quick Reference v1.0 | April 21, 2026**
