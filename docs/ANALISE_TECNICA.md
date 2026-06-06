# 📊 Análise Técnica: AWS Streaming Flight Radar

**Data**: June 5, 2026  
**Escopo**: Análise de pipeline streaming (Lambda → Kinesis → Flink → S3)  
**Status**: ⚠️ **3 erros críticos encontrados**

---

## 📋 Sumário Executivo

Pipeline de ingestão em tempo real de dados de voos usando OpenSky API. Arquitetura bem estruturada, mas com **3 erros críticos** que impedem a execução:

| Severidade | Erro | Arquivo | Linha |
|-----------|------|---------|-------|
| 🔴 CRÍTICO | Credenciais Secrets Manager não em IAM | `iam.tf` | - |
| 🔴 CRÍTICO | Variável de ambiente `OPENSKY_SECRET_ARN` faltando | `main.tf` | - |
| 🔴 CRÍTICO | Nome do arquivo SQL incorreto em app.py | `app.py` | 43 |
| 🔴 CRÍTICO | Stream ARN hardcoded em SQL | `01_source.sql` | 45 |
| 🟡 NÃO-CRÍTICO | Event time policy incorreta | `01_source.sql` | 37 |
| 🟡 NÃO-CRÍTICO | Over-permissive IAM para KMS | `iam.tf` | 77 |
| 🟡 NÃO-CRÍTICO | Sem retry logic em Kinesis PutRecords | `lambda_function.py` | 114 |

---

## 🏗️ Arquitetura

```
┌─────────────────────────────────────────────────────────────────┐
│                     AWS STREAMING PIPELINE                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────┐      ┌──────────────┐      ┌──────────────┐       │
│  │ OpenSky  │ ───→ │   Lambda     │ ───→ │   Kinesis    │       │
│  │   API    │      │  (ingest)    │      │   Streams    │       │
│  └──────────┘      └──────────────┘      └──────────────┘       │
│                                                     │             │
│                                                     ▼             │
│                                           ┌──────────────────┐   │
│                                           │ KDA (Flink SQL)  │   │
│                                           │ • Enriquecimento │   │
│                                           │ • Agregações     │   │
│                                           │ • Validação      │   │
│                                           └──────────────────┘   │
│                                                     │             │
│                                    ┌────────────────┼─────────┐  │
│                                    ▼                ▼         ▼  │
│                            ┌──────────┐  ┌──────────────┐  ... │
│                            │ S3 (1min)│  │ S3 (Altitude)│      │
│                            │Agregado  │  │ Distribuição │      │
│                            └──────────┘  └──────────────┘      │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔴 ERROS CRÍTICOS

### 1️⃣ **Lambda IAM: Falta Permissão de Secrets Manager**

**Arquivo**: [infra/modules/lambda_flights_raw/iam.tf](infra/modules/lambda_flights_raw/iam.tf)

**Problema**:
```terraform
# ❌ FALTANDO:
data "aws_iam_policy_document" "lambda_secrets_manager" {
  # Esta policy NÃO EXISTE!
}
```

A Lambda tenta executar:
```python
resp = secrets_client.get_secret_value(SecretId=secret_arn)
```

Mas não tem permissão IAM de `secretsmanager:GetSecretValue`.

**Impacto**: Lambda falhará com `AccessDenied` ao tentar ler credenciais OpenSky.

**Solução**:
```terraform
data "aws_iam_policy_document" "lambda_secrets_manager" {
  statement {
    actions = [
      "secretsmanager:GetSecretValue"
    ]
    resources = ["arn:aws:secretsmanager:*:*:secret:opensky/*"]
  }
}

resource "aws_iam_role_policy" "lambda_secrets_manager_policy" {
  name   = "${var.project_name}-lambda-secrets-manager-policy"
  role   = aws_iam_role.lambda_execution.id
  policy = data.aws_iam_policy_document.lambda_secrets_manager.json
}
```

---

### 2️⃣ **Lambda: Variável de Ambiente `OPENSKY_SECRET_ARN` Faltando**

**Arquivo**: [infra/modules/lambda_flights_raw/main.tf](infra/modules/lambda_flights_raw/main.tf#L1-L25)

**Problema**:
```terraform
environment {
  variables = {
    KINESIS_STREAM = var.kinesis_stream.name
    LOG_LEVEL      = "INFO"
    # ❌ FALTANDO: OPENSKY_SECRET_ARN
  }
}
```

A Lambda espera:
```python
secret_arn = os.environ.get("OPENSKY_SECRET_ARN")
if not secret_arn:
    logger.error("Missing OPENSKY_SECRET_ARN in environment variables")
    return None, None
```

**Impacto**: Lambda retorna `(None, None)` ao tentar autenticar, interrompendo pipeline.

**Solução**:
```terraform
environment {
  variables = {
    KINESIS_STREAM       = var.kinesis_stream.name
    OPENSKY_SECRET_ARN   = var.opensky_secret_arn  # ✅ Novo
    LOG_LEVEL            = "INFO"
  }
}
```

E adicionar variável no `variables.tf`:
```terraform
variable "opensky_secret_arn" {
  description = "ARN do Secrets Manager com credenciais OpenSky"
  type        = string
  sensitive   = true
}
```

---

### 3️⃣ **Flink app.py: Nome do Arquivo SQL Incorreto**

**Arquivo**: [app/flink-sql-application/app.py](app/flink-sql-application/app.py#L43)

**Problema**:
```python
sql_files = [
    ("source", os.path.join(base_dir, "01_source.sql")),
    ("view", os.path.join(base_dir, "02_enriched_view.sql")),
    ("sinks", os.path.join(base_dir, "03_sinks_kinesis.sql"))  # ❌ ERRADO
]
```

Arquivo real é `03_sinks_s3.sql`, não `03_sinks_kinesis.sql`.

**Impacto**: Flink falhará com `FileNotFoundError` ao iniciar.

**Solução**:
```python
sql_files = [
    ("source", os.path.join(base_dir, "01_source.sql")),
    ("view", os.path.join(base_dir, "02_enriched_view.sql")),
    ("sinks", os.path.join(base_dir, "03_sinks_s3.sql"))  # ✅ CORRETO
]
```

---

### 4️⃣ **SQL: Stream ARN Hardcoded**

**Arquivo**: [app/flink-sql-application/01_source.sql](app/flink-sql-application/01_source.sql#L45)

**Problema**:
```sql
'stream.arn' = 'arn:aws:kinesis:us-east-1:331504768406:stream/flight-radar-stream-flights',
```

ARN foi hardcoded com ID de conta específica.

**Impacto**: 
- Não portável entre contas AWS
- Quebra se nome do stream mudar
- Acoplamento desnecessário

**Solução**:
Usar parametrização via Terraform ou variáveis de ambiente:

```sql
-- Opção 1: Via variáveis de ambiente
'stream.arn' = '${kinesis_stream_arn}',

-- Opção 2: Via substitição de templates
'stream.arn' = '{KINESIS_STREAM_ARN}',
```

E no `app.py`, fazer substitição:
```python
with open(file_path, "r", encoding="utf-8") as f:
    sql_content = f.read()

# Substituir variáveis
sql_content = sql_content.replace(
    "{KINESIS_STREAM_ARN}", 
    os.environ.get("KINESIS_STREAM_ARN")
)
```

---

## 🟡 ERROS NÃO-CRÍTICOS (Melhores Práticas)

### 5️⃣ **SQL: Event Time Policy Incorreta**

**Arquivo**: [app/flink-sql-application/01_source.sql](app/flink-sql-application/01_source.sql#L37)

**Problema**:
```sql
event_time AS PROCTIME()  -- ❌ Errado para janelas time-based
```

`PROCTIME()` é "processing time" (hora que o Flink processa), não o timestamp real do evento.

Para agregações baseadas em tempo do evento (`TUMBLE`, `HOP`), deve-se usar `ROWTIME()` ou um timestamp explícito.

**Impacto**: Agregações podem ter dados em janelas erradas se houver atrasos.

**Solução**:
```sql
-- Opção 1: Usar timestamp do evento JSON
event_time AS CAST(COALESCE(
    TO_TIMESTAMP(REPLACE(time_position, 'T', ' ')),
    CURRENT_TIMESTAMP
) AS TIMESTAMP(3)) ROWTIME,

-- Opção 2: Simples - usar CURRENT_TIMESTAMP
event_time AS CURRENT_TIMESTAMP ROWTIME
```

---

### 6️⃣ **IAM: Over-Permissive para KMS**

**Arquivo**: [infra/modules/kinesis_analytics_flights/iam.tf](infra/modules/kinesis_analytics_flights/iam.tf#L77-L82)

**Problema**:
```terraform
statement {
  effect = "Allow"
  actions = [
    "kms:Decrypt",
    "kms:GenerateDataKey",
    "kms:DescribeKey"
  ]
  resources = ["*"]  # ❌ Muito permissivo
}
```

KMS não deveria ter `resources = ["*"]`.

**Impacto**: Viola princípio de "least privilege".

**Solução**:
```terraform
statement {
  effect = "Allow"
  actions = [
    "kms:Decrypt",
    "kms:GenerateDataKey",
    "kms:DescribeKey"
  ]
  resources = [
    "arn:aws:kms:${var.region}:${data.aws_caller_identity.current.account_id}:key/*"
  ]
  condition {
    test     = "StringEquals"
    variable = "kms:ViaService"
    values = [
      "kinesis.${var.region}.amazonaws.com",
      "s3.${var.region}.amazonaws.com"
    ]
  }
}
```

---

### 7️⃣ **Lambda: Sem Retry Logic em Kinesis PutRecords**

**Arquivo**: [app/lambda_flights_raw/src/lambda_function.py](app/lambda_flights_raw/src/lambda_function.py#L114-L138)

**Problema**:
```python
response = kinesis_client.put_records(
    StreamName=stream_name,
    Records=batch,
)
failed = response.get("FailedRecordCount", 0)
if failed > 0:
    all_ok = False
    logger.error(f"Batch {i//batch_size} - {failed}/{len(batch)} records failed")
    # ❌ Não faz retry!
```

Se houver falhas transientes, registros são perdidos.

**Impacto**: Perda de dados em caso de throttling ou falhas transientes do Kinesis.

**Solução**:
```python
import time
from botocore.exceptions import ClientError

def send_states_to_kinesis(json_resultado: dict, batch_size: int = 500, max_retries: int = 3) -> bool:
    """Envia estados para Kinesis com retry logic."""
    stream_name = os.environ.get("KINESIS_STREAM")
    if not stream_name:
        logger.error("KINESIS_STREAM environment variable not set")
        return False

    states = json_resultado["states"]
    if not states:
        logger.info("No states to send to Kinesis")
        return True

    records = [
        {
            "Data": json.dumps(state),
            "PartitionKey": state.get("icao24") or "unknown",
        }
        for state in states
    ]

    all_ok = True
    for i in range(0, len(records), batch_size):
        batch = records[i : i + batch_size]
        retry_count = 0
        
        while retry_count < max_retries:
            try:
                response = kinesis_client.put_records(
                    StreamName=stream_name,
                    Records=batch,
                )
                failed = response.get("FailedRecordCount", 0)
                
                if failed == 0:
                    logger.info(f"Batch {i//batch_size} - sent {len(batch)} records successfully")
                    break
                elif retry_count < max_retries - 1:
                    # Retry apenas registros falhados
                    failed_records = [
                        batch[j] for j, record in enumerate(response.get("Records", []))
                        if record.get("ErrorCode")
                    ]
                    batch = failed_records
                    retry_count += 1
                    logger.warning(f"Batch {i//batch_size} - retrying {len(batch)} failed records ({retry_count}/{max_retries})")
                    time.sleep(2 ** retry_count)  # Exponential backoff
                else:
                    all_ok = False
                    logger.error(f"Batch {i//batch_size} - {failed} records failed after {max_retries} retries")
                    
            except ClientError as e:
                if e.response['Error']['Code'] == 'ProvisionedThroughputExceededException':
                    retry_count += 1
                    if retry_count < max_retries:
                        wait_time = (2 ** retry_count) * 100  # milliseconds
                        logger.warning(f"Throttled. Retrying after {wait_time}ms ({retry_count}/{max_retries})")
                        time.sleep(wait_time / 1000)
                    else:
                        all_ok = False
                        logger.error(f"Batch {i//batch_size} - throttled, failed after {max_retries} retries: {e}")
                else:
                    all_ok = False
                    logger.error(f"Error sending batch {i//batch_size}: {e}")
                    break

    return all_ok
```

---

## 🟢 PONTOS POSITIVOS

### ✅ Boas Práticas Encontradas

1. **Estrutura de Projeto Clara**
   - Separação entre `app/`, `infra/`, `scripts/`
   - Módulos Terraform bem organizados

2. **Segurança com Secrets Manager**
   - Credenciais não hardcoded
   - Uso apropriado de AWS Secrets Manager

3. **SQL Bem Documentado**
   - Comments explicando cada coluna
   - Notas técnicas sobre watermarks
   - Descrição de transformações

4. **Processamento Flink Robusto**
   - Tratamento de erros de parse JSON
   - Conversão de unidades (metros↔pés, m/s↔knots)
   - Classificações de fase de voo

5. **IAM com Least Privilege (quase)**
   - Separação clara de roles para Lambda e KDA
   - Policies específicas por serviço

6. **Logging Estruturado**
   - CloudWatch logs configurado
   - Logging em nível apropriado

---

## 📝 RECOMENDAÇÕES ADICIONAIS

### Implementar Pattern de Dead Letter Queue (DLQ)
```terraform
# Adicionar DLQ para Kinesis
resource "aws_kinesis_stream" "flights_dlq" {
  name = "${var.project_name}-flights-dlq"
  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }
}
```

### Adicionar Monitoring e Alarms
```terraform
# CloudWatch Alarm para Lambda errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project_name}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_actions       = [aws_sns_topic.alerts.arn]
}
```

### Melhorar Tratamento de Exceções na Lambda
```python
def lambda_handler(event, context):
    """Main handler com melhor tratamento de erro."""
    try:
        # 1. Get credentials
        access_token = get_opensky_access_token()
        if not access_token:
            logger.error("Failed to get access token")
            return {
                "statusCode": 401,
                "body": json.dumps({"error": "Authentication failed"})
            }

        # 2. Get states
        states = get_opensky_states(access_token)
        if not states:
            logger.warning("No states retrieved")
            return {
                "statusCode": 200,
                "body": json.dumps({"message": "No states available", "count": 0})
            }

        # 3. Convert and send
        json_data = convert_states_response_to_json(states)
        success = send_states_to_kinesis(json_data)
        
        if success:
            return {
                "statusCode": 200,
                "body": json.dumps({
                    "message": "Success",
                    "states_sent": len(states)
                })
            }
        else:
            return {
                "statusCode": 500,
                "body": json.dumps({
                    "error": "Partial failure sending to Kinesis",
                    "states_attempted": len(states)
                })
            }
    
    except Exception as e:
        logger.exception("Unhandled exception in lambda_handler")
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)})
        }
```

### Adicionar Testes Unitários
```python
# tests/test_models.py
import pytest
from datetime import datetime
from app.lambda_flights_raw.src.utils.models import StateVector

def test_state_vector_from_api_response():
    """Test parsing API response."""
    api_response = [
        "hexcode",  # icao24
        "callsign",
        "Country",
        1704067200,  # time_position
        1704067200,  # last_contact
        10.5,  # longitude
        40.5,  # latitude
        3000,  # altitude
        False,  # on_ground
        200,  # velocity
        90,  # heading
        0,  # vertical_rate
        3100,  # geo_altitude
        None,  # unused
        "1234",  # squawk
        False,  # spi
        0,  # position_source
    ]
    
    state = StateVector.from_api_response(api_response)
    
    assert state.icao24 == "hexcode"
    assert state.latitude == 40.5
    assert state.altitude == 3000
```

### Adicionar Terraform Validation
```bash
# Dentro de scripts/
#!/bin/bash
# validate_terraform.sh

terraform -chdir="./infra" init
terraform -chdir="./infra" validate
terraform -chdir="./infra" fmt -check
```

---

## 📊 Checklist de Correção

- [ ] **CRÍTICO**: Adicionar `secretsmanager:GetSecretValue` ao IAM da Lambda
- [ ] **CRÍTICO**: Adicionar `OPENSKY_SECRET_ARN` à variável de ambiente da Lambda
- [ ] **CRÍTICO**: Corrigir nome de arquivo SQL em `app.py` (`03_sinks_kinesis.sql` → `03_sinks_s3.sql`)
- [ ] **CRÍTICO**: Parametrizar ARN do Kinesis em `01_source.sql`
- [ ] Corrigir `PROCTIME()` → `ROWTIME` em `01_source.sql`
- [ ] Restringir permissões KMS em IAM da KDA
- [ ] Implementar retry logic em `send_states_to_kinesis()`
- [ ] Adicionar DLQ para dados não processáveis
- [ ] Adicionar CloudWatch alarms
- [ ] Adicionar testes unitários
- [ ] Adicionar validação de Terraform em CI/CD

---

## 🚀 Próximos Passos

1. **Curto prazo** (hoje):
   - Corrigir 4 erros críticos
   - Testar deployment com Terraform
   
2. **Médio prazo** (semana):
   - Implementar retry logic
   - Adicionar monitoring/alarms
   - Criar testes unitários

3. **Longo prazo** (backlog):
   - Migrar para estado remoto (Terraform Cloud/S3)
   - Implementar GitOps para deploys
   - Adicionar testes de integração com Localstack
   - Otimizar custos (Kinesis ON_DEMAND → provisioned com auto-scaling)

---

**Gerado em**: June 5, 2026  
**Versão da Análise**: 1.0
