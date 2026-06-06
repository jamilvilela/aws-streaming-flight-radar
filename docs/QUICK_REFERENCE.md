# 🎯 Quick Reference - AWS Streaming Flight Radar

## Estrutura do Pipeline

```
Lambda (OpenSky) → Kinesis → Flink SQL (KDA) → S3
   ↓                ↓
Secrets Mgr    JSON Records      ↓ Enriquecimento
               PutRecords        ↓ Agregações
                             4 Sinks S3
```

## 🔑 Variáveis de Ambiente

### Lambda
```bash
KINESIS_STREAM       = "flight-radar-stream-flights"
OPENSKY_SECRET_ARN   = "arn:aws:secretsmanager:..."
LOG_LEVEL            = "INFO"
```

### KDA / Flink
```bash
KINESIS_STREAM_ARN   = "arn:aws:kinesis:us-east-1:ACCOUNT:stream/flight-radar-stream-flights"
AWS_REGION           = "us-east-1"
restart-strategy     = "none"
```

## 📋 Checklist Pré-Deploy

- [ ] Secrets Manager criado com `client_id` e `client_secret`
- [ ] `opensky_secret_arn` em `terraform.tfvars`
- [ ] S3 buckets para workspace e landing criados
- [ ] `terraform validate` passou ✅
- [ ] `terraform plan` mostra recursos a criar
- [ ] Nenhum erro de hardcoding em arquivos SQL

## 🔍 Verificações Pós-Deploy

### 1. Lambda
```bash
# Testar invocação
aws lambda invoke --function-name flight-radar-stream-ingest-flights /tmp/resp.json

# Ver logs
aws logs tail /aws/lambda/flight-radar-stream-ingest-flights --follow
```

### 2. Kinesis
```bash
# Verificar dados
aws kinesis get-shard-iterator --stream-name flight-radar-stream-flights \
  --shard-id shardId-000000000000 --shard-iterator-type LATEST | \
  jq -r '.ShardIterator' | \
  xargs -I {} aws kinesis get-records --shard-iterator {}
```

### 3. Flink / KDA
```bash
# Status
aws kinesisanalyticsv2 describe-application \
  --application-name flight-radar-stream-kda-flights

# Logs
aws logs tail /aws/kinesisanalytics/flight-radar-stream-kda-flights --follow

# Iniciar
aws kinesisanalyticsv2 start-application \
  --application-name flight-radar-stream-kda-flights
```

### 4. S3
```bash
# Ver dados de saída
aws s3 ls s3://lakehouse-landing-ACCOUNT_ID/opensky/

# Contar Parquet files
aws s3 ls s3://lakehouse-landing-ACCOUNT_ID/opensky/flights-positions-1min/ --recursive | wc -l
```

## 🆘 Erros Comuns & Soluções

| Erro | Causa | Solução |
|------|-------|---------|
| `AccessDenied: secretsmanager` | Falta IAM policy | Verificar `lambda_secrets_manager_policy` em `iam.tf` |
| `FileNotFoundError: 03_sinks_kinesis.sql` | Nome errado | Arquivo é `03_sinks_s3.sql` |
| `Cannot resolve variable ${KINESIS_STREAM_ARN}` | Env var não set | Adicionar em KDA environment_properties |
| `ProvisionedThroughputExceededException` | Throttling | Retry logic já implementado |
| `PROCTIME() in TUMBLE` | Event time errada | Usar `CURRENT_TIMESTAMP AS event_time ROWTIME` |

## 📊 Monitoramento Essencial

### CloudWatch Metrics
```bash
# Lambda
- Invocations
- Errors
- Duration
- Throttles

# Kinesis
- GetRecords.IteratorAgeMilliseconds
- WriteProvisionedThroughputExceeded
- ReadProvisionedThroughputExceeded

# KDA
- ApplicationFlinkApplicationFailure
- JobManagerSideMetricsBackPressuredTimeMsPerSecond
```

### Alarms Críticos
```hcl
- Lambda errors > 5 em 5 min → SNS
- Kinesis iterator age > 60s → SNS
- KDA failed → SNS
- S3 write failures → SNS
```

## 🔐 Segurança

### IAM Least Privilege
✅ Lambda: Apenas `s3:GetObject`, `kinesis:PutRecords`, `secretsmanager:GetSecretValue`
✅ KDA: Apenas `kinesis:*` e `s3:*` para buckets específicos
✅ KMS: Apenas para Kinesis e S3 (conditions aplicadas)

### Secrets Management
✅ Nunca hardcode credenciais
✅ Use `aws_secretsmanager_secret` no Terraform
✅ Rotate credentials periodicamente
✅ Usar `sensitive = true` em variáveis

## 💰 Otimização de Custos

### Kinesis
- ON_DEMAND: bom para dev ($0.40/GB)
- PROVISIONED: melhor para prod conhecida ($0.34/shard-hour)

### KDA
- Cobrança por KPU/hora
- 1 KPU = ~50k eventos/min
- Auto-scaling reduz custos em off-peak

### S3
- Parquet format vs JSON (50% compressão)
- Lifecycle policies para archive (Glacier após 90d)
- Versioning OFF para economia

## 📈 Escalabilidade

```
Low Volume:        Kinesis 1 shard + KDA 1 KPU
Medium Volume:     Kinesis 5 shards + KDA 4 KPU
High Volume:       Kinesis 10+ shards + KDA 8+ KPU
```

## 🧪 Testes Locais

### LocalStack (Docker)
```bash
docker run -d --name localstack -p 4566:4566 localstack/localstack

# Criar recursos localmente
aws --endpoint-url=http://localhost:4566 \
  kinesis create-stream --stream-name local-flights --shard-count 1
```

### Testes Python
```python
import pytest
from app.lambda_flights_raw.src.utils.models import StateVector

def test_state_vector_parsing():
    api_resp = ["hexcode", "callsign", "BR", 1704067200, ...]
    state = StateVector.from_api_response(api_resp)
    assert state.icao24 == "hexcode"
    assert state.latitude == 40.5
```

## 📚 Recursos Úteis

- [OpenSky Network API](https://openskynetwork.github.io/opensky-api/)
- [Flink SQL Docs](https://nightlies.apache.org/flink/flink-docs-master/docs/dev/table/sql/overview/)
- [Kinesis Data Analytics](https://docs.aws.amazon.com/kinesisanalytics/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## 🚀 Comandos Rápidos

```bash
# Full deployment
cd infra && terraform apply

# Destroy (dev only!)
terraform destroy

# Check state
terraform show

# Import existing resource
terraform import aws_kinesis_stream.flights flight-radar-stream-flights

# Format all
terraform fmt -recursive

# Validate
terraform validate
```

## 📞 Troubleshooting Rápido

```bash
# Check Lambda execution
aws logs tail /aws/lambda/flight-radar-stream-ingest-flights --follow --filter-pattern "ERROR"

# Monitor Kinesis
watch -n 1 'aws kinesis list-streams'

# Check Flink status
aws kinesisanalyticsv2 list-applications | jq '.ApplicationSummaries[] | select(.ApplicationName=="flight-radar-stream-kda-flights")'

# Debug S3 permissions
aws s3 ls s3://lakehouse-landing-ACCOUNT_ID/opensky/ --debug 2>&1 | grep -i "error\|denied"
```

---

**Documento**: Quick Reference v1.0  
**Atualizado**: June 5, 2026  
**Responsável**: Data Engineering Team
