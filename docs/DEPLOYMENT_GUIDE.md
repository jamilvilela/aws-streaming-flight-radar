# 🚀 Guia de Deployment - AWS Streaming Flight Radar

**Status**: ✅ Análise completa + 4 erros críticos corrigidos

---

## 📋 Correções Aplicadas

Todos os arquivos foram corrigidos com as seguintes mudanças:

### ✅ Correção 1: Secrets Manager IAM Policy
**Arquivo**: `infra/modules/lambda_flights_raw/iam.tf`

```terraform
# ✅ ADICIONADO: Permissão para ler credenciais do Secrets Manager
resource "aws_iam_role_policy" "lambda_secrets_manager_policy" {
  name   = "${var.project_name}-lambda-secrets-manager-policy"
  role   = aws_iam_role.lambda_execution.id
  policy = data.aws_iam_policy_document.lambda_secrets_manager.json
}
```

### ✅ Correção 2: Variável de Ambiente OPENSKY_SECRET_ARN
**Arquivo**: `infra/modules/lambda_flights_raw/main.tf`

```terraform
environment {
  variables = {
    KINESIS_STREAM       = var.kinesis_stream.name
    OPENSKY_SECRET_ARN   = var.opensky_secret_arn  # ✅ ADICIONADO
    LOG_LEVEL            = "INFO"
  }
}
```

**Arquivo**: `infra/modules/lambda_flights_raw/variables.tf`

```terraform
variable "opensky_secret_arn" {
  description = "ARN do Secrets Manager com credenciais OpenSky"
  type        = string
  sensitive   = true
}
```

### ✅ Correção 3: Nome Correto do Arquivo SQL
**Arquivo**: `app/flink-sql-application/app.py`

```python
# ❌ ANTES:
("sinks", os.path.join(base_dir, "03_sinks_kinesis.sql"))  # Arquivo não existe!

# ✅ DEPOIS:
("sinks", os.path.join(base_dir, "03_sinks_s3.sql"))  # ✅ Correto
```

### ✅ Correção 4: Parametrização de ARN Kinesis + Substitução de Variáveis
**Arquivo**: `app/flink-sql-application/01_source.sql`

```sql
-- ❌ ANTES: ARN hardcoded
'stream.arn' = 'arn:aws:kinesis:us-east-1:331504768406:stream/flight-radar-stream-flights',

-- ✅ DEPOIS: Parametrizado
'stream.arn' = '${KINESIS_STREAM_ARN}',
'aws.region' = '${AWS_REGION}',
```

**Arquivo**: `app/flink-sql-application/app.py`

```python
# ✅ ADICIONADO: Substitui variáveis no SQL antes de executar
kinesis_stream_arn = os.environ.get("KINESIS_STREAM_ARN", "")
aws_region = os.environ.get("AWS_REGION", "us-east-1")

if not kinesis_stream_arn:
    log("ERROR: KINESIS_STREAM_ARN environment variable not set")
    sys.exit(1)

# Perform variable substitution
sql_content = sql_content.replace("${KINESIS_STREAM_ARN}", kinesis_stream_arn)
sql_content = sql_content.replace("${AWS_REGION}", aws_region)
```

### ✅ Melhorias Adicionais

1. **Event Time Policy (01_source.sql)**
   - Corrigido `PROCTIME()` → `CURRENT_TIMESTAMP AS event_time ROWTIME`

2. **KMS IAM Policy (kinesis_analytics_flights/iam.tf)**
   - Restringido de `resources = ["*"]` para ARNs específicas com conditions

3. **Retry Logic (lambda_flights_raw/lambda_function.py)**
   - Implementado exponential backoff com retry de registros falhados
   - Suporte a throttling do Kinesis

4. **Variáveis Terraform**
   - Adicionada variável `kinesis_stream_arn` em KDA
   - Adicionada variável `opensky_secret_arn` no root
   - Passar variáveis via environment properties da KDA

---

## 📦 Pré-requisitos para Deployment

### 1. Criar Secrets Manager
```bash
# Criar secret com credenciais OpenSky
aws secretsmanager create-secret \
  --name opensky-credentials \
  --secret-string '{
    "client_id": "seu_client_id",
    "client_secret": "seu_client_secret"
  }'

# Guardar o ARN retornado (será usado em terraform.tfvars)
# Exemplo: arn:aws:secretsmanager:us-east-1:123456789012:secret:opensky-credentials-AbCdEf
```

### 2. S3 Bucket para Artefatos Terraform
```bash
# Criar bucket para artefatos Flink
aws s3 mb s3://lakehouse-workspace-${AWS_ACCOUNT_ID} --region us-east-1

# Criar bucket para S3 sinks do Flink
aws s3 mb s3://lakehouse-landing-${AWS_ACCOUNT_ID} --region us-east-1
```

### 3. Arquivos de Configuração

**Arquivo**: `infra/terraform.tfvars`

```hcl
project_name              = "flight-radar-stream"
aws_region                = "us-east-1"
environment               = "development"

# ARN do Secret Manager (obtido no passo 1)
opensky_secret_arn        = "arn:aws:secretsmanager:us-east-1:123456789012:secret:opensky-credentials-AbCdEf"

# Kinesis Streams
kinesis_streams = {
  flights = {
    name = "flight-radar-stream-flights"
    mode = "ON_DEMAND"  # ou "PROVISIONED" com shard count
  },
  flights_rt = {
    name = "flight-radar-stream-flights-rt"
    mode = "ON_DEMAND"
  }
}

# Lambda Functions
lambda_functions = {
  flights_raw = {
    name              = "ingest-flights"
    handler           = "lambda_function.lambda_handler"
    runtime           = "python3.11"
    timeout           = 60
    memory_size       = 512
    ephemeral_storage = 512
    tags              = {}
  }
}

# S3 Buckets
buckets = {
  workspace = "lakehouse-workspace-${data.aws_caller_identity.current.account_id}"
  landing   = "lakehouse-landing-${data.aws_caller_identity.current.account_id}"
}

# Flink Configuration
flink_config = {
  parallelism = 1     # 1 KPU para dev, 4-8 para produção
  auto_start  = false # false em dev, true em CI/CD
}

# Tags
tags = {
  Environment = "development"
  Project     = "flight-radar"
  Team        = "data-engineering"
  CreatedAt   = "2026-01-17"
}
```

---

## 🚀 Passos de Deployment

### 1. Validar Terraform
```bash
cd infra

# Inicializar Terraform
terraform init

# Validar sintaxe
terraform validate

# Formatar código
terraform fmt -recursive

# Plan para ver o que será criado
terraform plan -out=tfplan
```

### 2. Deploy Terraform
```bash
# Aplicar plano
terraform apply tfplan

# Ou diretamente (sem plano salvo)
terraform apply

# Quando perguntado, digitar "yes"
```

### 3. Configurar Lambda com EventBridge (Agendamento)
```bash
# A Lambda foi criada. Agora configurar EventBridge via console ou CLI:

aws events put-rule \
  --name flight-radar-ingest-schedule \
  --schedule-expression "rate(5 minutes)" \
  --state ENABLED

aws events put-targets \
  --rule flight-radar-ingest-schedule \
  --targets "Id"="1","Arn"="arn:aws:lambda:us-east-1:ACCOUNT_ID:function:flight-radar-stream-ingest-flights","RoleArn"="arn:aws:iam::ACCOUNT_ID:role/EventBridgeInvokeRole"
```

### 4. Deploy Flink SQL Application
```bash
# Faz deploy das scripts SQL para S3
cd scripts
bash deploy_flink_sql.sh start
```

### 5. Testar Pipeline
```bash
# Invocar Lambda manualmente
aws lambda invoke \
  --function-name flight-radar-stream-ingest-flights \
  /tmp/response.json

cat /tmp/response.json

# Verificar logs
aws logs tail /aws/lambda/flight-radar-stream-ingest-flights --follow

# Monitorar Kinesis
aws kinesis describe-stream \
  --stream-name flight-radar-stream-flights

# Verificar status Flink
aws kinesisanalyticsv2 describe-application \
  --application-name flight-radar-stream-kda-flights

# Ver logs Flink
aws logs tail /aws/kinesisanalytics/flight-radar-stream-kda-flights --follow
```

---

## 🔍 Validações Importantes

### Antes de Deploy

- [ ] `terraform validate` passa
- [ ] Secret Manager criado com `client_id` e `client_secret`
- [ ] S3 buckets criados
- [ ] `terraform.tfvars` preenchido com valores corretos
- [ ] Nenhum hardcoding de credenciais

### Após Deploy

- [ ] Lambda consegue ler Secrets Manager
- [ ] Lambda consegue enviar para Kinesis
- [ ] Kinesis recebe eventos
- [ ] KDA Flink inicia com status RUNNING
- [ ] Logs do Flink não mostram erros
- [ ] Dados aparecem em S3

---

## 📊 Monitoramento

### CloudWatch Dashboards
```bash
# Criar dashboard personalizado
aws cloudwatch put-dashboard \
  --dashboard-name flight-radar-pipeline \
  --dashboard-body file://dashboard.json
```

### Alarms Críticos
- Lambda errors > 5 em 5 min
- Kinesis iterator age > 60s
- KDA application failed
- S3 write failures

---

## 🔧 Troubleshooting

### Lambda falha ao ler Secrets Manager
```
Erro: "User: arn:aws:iam::... is not authorized to perform: secretsmanager:GetSecretValue"

Solução: Verificar se IAM policy foi criada
aws iam list-role-policies --role-name flight-radar-stream-lambda-execution-role
```

### Flink não encontra arquivo SQL
```
Erro: FileNotFoundError: 03_sinks_kinesis.sql

Solução: Corrigi arquivo de 03_sinks_kinesis.sql → 03_sinks_s3.sql
         Verificar se app.py foi atualizado
```

### ARN do Kinesis hardcoded
```
Erro: Connection refused ao Kinesis

Solução: Corrigi parametrização em 01_source.sql
         Verificar se environment_properties tem KINESIS_STREAM_ARN
```

---

## 📈 Escalabilidade

### Aumentar Throughput Kinesis
```hcl
# Em terraform.tfvars
kinesis_streams = {
  flights = {
    name = "flight-radar-stream-flights"
    mode = "PROVISIONED"  # Muda para provisioned
    shard_count = 5       # Aumentar shards
  }
}
```

### Aumentar Paralelismo Flink
```hcl
flink_config = {
  parallelism = 8  # De 1 para 8 KPUs
  auto_start  = true
}
```

### Auto-scaling
```hcl
# Já está configurado em:
# infra/modules/kinesis_analytics_flights/main.tf
parallelism_configuration {
  auto_scaling_enabled = true
}
```

---

## 📝 Logs Importantes

- **Lambda Logs**: `/aws/lambda/flight-radar-stream-ingest-flights`
- **Kinesis Analytics**: `/aws/kinesisanalytics/flight-radar-stream-kda-flights`
- **S3 Sinks**: `s3://lakehouse-landing-ACCOUNT_ID/opensky/`

---

## ✅ Checklist Final

- [ ] Todos os 4 erros críticos foram corrigidos
- [ ] Terraform valida sem erros
- [ ] tfplan pode ser aplicado
- [ ] Lambda consegue ler secrets
- [ ] Kinesis recebe eventos
- [ ] Flink processa dados
- [ ] S3 tem dados de saída
- [ ] Alarmes estão configurados
- [ ] Documentação atualizada

---

**Próximas Melhorias** (Backlog):
- [ ] Testes unitários para Lambda
- [ ] Testes de integração com LocalStack
- [ ] CI/CD pipeline com GitHub Actions
- [ ] Dead Letter Queue para dados inválidos
- [ ] Redshift Spectrum queries nos dados S3
- [ ] Dashboard QuickSight

---

**Versão**: 1.0  
**Data**: June 5, 2026
