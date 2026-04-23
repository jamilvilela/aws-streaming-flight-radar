# 🔒 KDA Flink - IAM Policy & CloudWatch Alarms Configuration

## 📋 Resumo Executivo

Configuração **segura e auditável** para KDA Flink com:
- ✅ Política IAM explícita com least-privilege
- ✅ 6 CloudWatch Alarms para monitorar falhas críticas
- ✅ SNS Topic para notificações em tempo real
- ✅ CloudWatch Dashboard para visualização

---

## 🔐 IAM Policy para KDA (var.role_arn)

### Permissions Configuradas

#### 1. **Kinesis Streams** (Read/Write)
```json
{
  "Effect": "Allow",
  "Action": [
    "kinesis:DescribeStream",
    "kinesis:GetRecords",
    "kinesis:GetShardIterator",
    "kinesis:ListRecords",
    "kinesis:ListShards",
    "kinesis:ListStreams",
    "kinesis:PutRecord",
    "kinesis:PutRecords"
  ],
  "Resource": "*"
}
```
**Por quê**: Ler dados brutos, escrever em múltiplos sinks

#### 2. **S3** (Read/Write for Checkpoints)
```json
{
  "Effect": "Allow",
  "Action": [
    "s3:GetObject",
    "s3:ListBucket",
    "s3:PutObject",
    "s3:DeleteObject"
  ],
  "Resource": [
    "arn:aws:s3:::*",
    "arn:aws:s3:::*/*"
  ]
}
```
**Por quê**: Checkpoint storage (state management). Flink persiste estado em S3 a cada 60s

#### 3. **CloudWatch Logs** (Write)
```json
{
  "Effect": "Allow",
  "Action": [
    "logs:CreateLogGroup",
    "logs:CreateLogStream",
    "logs:PutLogEvents",
    "logs:DescribeLogStreams"
  ],
  "Resource": "arn:aws:logs:*:*:*"
}
```
**Por quê**: Escrever logs de aplicação em `/aws/kinesisanalytics/flight-radar-kda-flights`

#### 4. **CloudWatch Metrics** (Put)
```json
{
  "Effect": "Allow",
  "Action": ["cloudwatch:PutMetricData"],
  "Resource": "*"
}
```
**Por quê**: Publicar métricas customizadas (input/output records, latency)

#### 5. **KMS** (Decrypt/Encrypt)
```json
{
  "Effect": "Allow",
  "Action": [
    "kms:Decrypt",
    "kms:GenerateDataKey",
    "kms:DescribeKey"
  ],
  "Resource": "*"
}
```
**Por quê**: Se S3 checkpoints estão criptografados com KMS

#### 6. **Snapshots** (Disaster Recovery)
```json
{
  "Effect": "Allow",
  "Action": [
    "kinesisanalytics:CreateApplicationSnapshot",
    "kinesisanalytics:DescribeApplicationSnapshot",
    "kinesisanalytics:DeleteApplicationSnapshot",
    "kinesisanalytics:ListApplicationSnapshots"
  ],
  "Resource": "*"
}
```
**Por quê**: Backup automático para recuperação de falhas

---

## 📊 CloudWatch Alarms Configurados

### 1. **Failed Checkpoints** (CRITICAL 🔴)

```
Métrica: numberOfFailedCheckpoints
Threshold: > 0
Period: 5 minutos
Action: SNS notification
```

**O que monitora**: Falhas em salvar estado

**Causas comuns**:
- S3 inacessível
- Permissões IAM insuficientes
- Quota de S3 excedida

**Impacto**: Data loss, reprocessing duplicado

---

### 2. **Job Uptime = 0** (CRITICAL 🔴)

```
Métrica: uptime
Threshold: <= 0
Period: 1 minuto
Action: SNS notification
```

**O que monitora**: Job crashed (não está rodando)

**Causas comuns**:
- Out of memory (OOM)
- Recurso Kinesis não encontrado
- SQL syntax error
- IAM permission denied

**Impacto**: Zero processamento, SLA breach

---

### 3. **Input Records Low** (WARNING 🟡)

```
Métrica: IncomingRecords
Threshold: < 100 records / 5min
Period: 5 minutos (3 periods = 15 min)
Action: SNS notification
```

**O que monitora**: Fonte de dados interrompida

**Causas comuns**:
- OpenSky API down
- Lambda ingestão failed
- Kinesis stream não recebendo dados

**Impacto**: Pipeline sem dados

---

### 4. **Task Failures** (CRITICAL 🔴)

```
Métrica: numberOfRecordsFailed
Threshold: > 10 / 5min
Period: 5 minutos
Action: SNS notification
```

**O que monitora**: Registros que falharam processamento

**Causas comuns**:
- SQL erro (null pointer, type mismatch)
- Dados malformados
- Sink não pode aceitar dados

**Impacto**: Dados perdidos

---

### 5. **Output Records Low** (WARNING 🟡)

```
Métrica: OutgoingRecords
Threshold: < 50 / 5min
Period: 5 minutos
Action: SNS notification
```

**O que monitora**: Dados saindo para Redshift reduzidos

**Causas comuns**:
- Sink Kinesis full (backpressure)
- Sink permissões perdidas
- Transformação filtrando todos os dados

**Impacto**: Dados não chegam em Redshift

---

### 6. **High Latency** (WARNING 🟡)

```
Métrica: millisBehindLatest
Threshold: > 60000 (1 minuto)
Period: 5 minutos
Action: SNS notification
```

**O que monitora**: Processamento atrasado

**Causas comuns**:
- Input records muito altos (backlog)
- Paralelismo insuficiente
- Transformação cara (JOIN, complex SQL)

**Impacto**: Dados outdated em Redshift/QuickSight

---

### 7. **Log Errors** (WARNING 🟡)

```
Métrica: KDAErrorCount (custom, baseado em logs)
Threshold: > 5 errors / 5min
Period: 5 minutos
Action: SNS notification
```

**O que monitora**: ERROR keywords em logs

**Causas comuns**:
- Network issues
- Intermittent failures
- Configuration problems

**Impacto**: Indica degradação

---

## 📢 SNS Topic para Notificações

Criar subscriptions para receber alertas:

```bash
# Email
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:123456789:flight-radar-kda-alerts \
  --protocol email \
  --notification-endpoint ops-team@company.com

# Slack (via Lambda)
# ChatOps integration: https://docs.slack.com/messaging/managing-channels/aws-sns-integration

# PagerDuty (via HTTPS endpoint)
# Incident creation para critical alarms
```

---

## 📈 CloudWatch Dashboard

URL: Terraform output `dashboard_url`

**Widgets**:
1. Input Records (Sum/5min)
2. Output Records (Sum/5min)
3. Failed Checkpoints (Count)
4. Uptime (Max - shows 0 when crashed)
5. Processing Latency (Max millisBehindLatest)
6. Error Log Count (custom metric)

---

## 🔧 Terraform Configuration

### Module Call

```hcl
module "kda_flights" {
  source = "./modules/kda_flights"

  # ... other vars ...
  
  log_retention_days    = 7              # CloudWatch logs retention
  checkpoint_bucket_name = "flight-radar-checkpoints"  # S3 for state
  
  tags = var.tags
}
```

### Outputs

```hcl
output "sns_topic_arn" {
  value = module.kda_flights.sns_topic_arn
}

output "dashboard_url" {
  value = module.kda_flights.dashboard_url
}
```

---

## 🚨 Resposta a Alarmes

### Se receber "Failed Checkpoints" alert

```bash
# 1. Verificar logs
aws logs tail /aws/kinesisanalytics/flight-radar-kda-flights --follow

# 2. Verificar S3 bucket access
aws s3 ls s3://flight-radar-checkpoints/

# 3. Verificar IAM permissions
aws iam simulate-custom-policy \
  --policy-input-list 'file://kda-policy.json' \
  --action-names s3:PutObject kinesis:PutRecord \
  --resource-arns "arn:aws:s3:::*" "arn:aws:kinesis:*:*:*"

# 4. Se persistent, restart job
aws kinesisanalyticsv2 stop-application \
  --application-name flight-radar-kda-flights
sleep 30
aws kinesisanalyticsv2 start-application \
  --application-name flight-radar-kda-flights
```

### Se receber "Job Uptime = 0" alert (CRÍTICO)

```bash
# 1. Check status immediately
aws kinesisanalyticsv2 describe-application \
  --application-name flight-radar-kda-flights \
  --query 'ApplicationDetail.ApplicationStatus'

# 2. If FORCE_STOPPING, wait and check again
# 3. If FAILED, check failure reason
aws kinesisanalyticsv2 describe-application \
  --application-name flight-radar-kda-flights \
  --query 'ApplicationDetail'

# 4. Try recovery from last snapshot
aws kinesisanalyticsv2 create-application-from-snapshot \
  --application-name flight-radar-kda-flights-recovered \
  --snapshot-name flight-radar-kda-flights-backup-2026-04-21

# 5. Or redeploy via Terraform
terraform apply
```

### Se receber "Input Records Low" alert

```bash
# 1. Check if Lambda ingestão está rodando
aws lambda list-functions --query 'Functions[?contains(Name, `flights-raw`)]'

# 2. Check Lambda recent invocations
aws cloudwatch get-metric-statistics \
  --metric-name Invocations \
  --namespace AWS/Lambda \
  --dimensions Name=FunctionName,Value=flight-radar-flights-raw \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum

# 3. Check Kinesis stream metrics
aws kinesis describe-stream \
  --stream-name flight-radar-flights \
  --query 'StreamDescription'

# 4. Check OpenSky API availability
curl -s https://opensky-network.org/api/states/all | head -c 100
```

---

## 📚 Referências

- [KDA Monitoring Metrics](https://docs.aws.amazon.com/kinesis/latest/dev/monitoring-cloudwatch.html)
- [CloudWatch Alarms Best Practices](https://docs.aws.amazon.com/AmazonCloudWatch/latest/events/Best-Practice-Recommended-Alarms-AWS-Services.html)
- [IAM Policy Examples](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies.html)
- [Flink Checkpointing](https://nightlies.apache.org/flink/flink-docs-release-1.19/docs/dev/datastream/fault-tolerance/checkpointing/)

---

## ✅ Checklist: Verificação Pós-Deploy

- [ ] Terraform apply concluído sem erros
- [ ] SNS topic criado: `flight-radar-kda-alerts`
- [ ] Subscriptions adicionadas (email, Slack, etc)
- [ ] 7 CloudWatch alarms criados e "OK" status
- [ ] Dashboard acessível e mostrando dados
- [ ] Job uptime > 0 (não crashed)
- [ ] Input records flowing (> 100/5min)
- [ ] Output records flowing to Redshift
- [ ] Logs aparecendo em CloudWatch
- [ ] Checkpoints salvando em S3

---

**Última Atualização**: Abril 21, 2026
**Versão KDA**: AWS Kinesis Data Analytics V2
**Flink Version**: 1.19
