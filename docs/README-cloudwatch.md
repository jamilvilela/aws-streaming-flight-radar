# ☁️ CloudWatch Monitoring Module

Módulo para monitoramento completo do pipeline de streaming: **Kinesis → Firehose → S3/OpenSearch**

## 📊 Métricas Monitoradas

### Kinesis Stream
- `IncomingRecords` / `IncomingBytes`: Volume de dados entrando
- `GetRecords.IteratorAgeMilliseconds`: Backlog de processamento ⚠️
- `WriteProvisionedThroughputExceeded`: Throttling de escrita
- `ReadProvisionedThroughputExceeded`: Throttling de leitura

### Kinesis Firehose (S3)
- `DeliveryToS3.Success` / `Failed`: Taxa de entrega
- `IncomingRecords` / `IncomingBytes`: Volume processado
- `ProcessingDuration`: Tempo de processamento

### Kinesis Firehose (OpenSearch)
- `DeliveryToOpenSearch.Success` / `Failed`: Taxa de indexação
- `Documents.Dropped`: Documentos descartados 🚨
- `SuccessLatency`: Latência de entrega

### Lambda Functions
- `Invocations` / `Errors`: Executions e falhas
- `Duration` (p50, p95, p99): Performance
- `Throttles`: Limites de concorrência atingidos

### OpenSearch Domain
- `CPUUtilization` / `JVMMemoryPressure`: Saúde do cluster
- `IndexingRate` / `SearchRate`: Throughput de operações
- `IndexingFailures`: Falhas de indexação

## 🚨 Alarmes Configurados

| Severidade | Condição | Ação |
|------------|----------|------|
| 🔴 Critical | Iterator Age > 60s | SNS + PagerDuty |
| 🔴 Critical | Delivery Failures > 0 | SNS + PagerDuty |
| 🟡 Warning | Success Rate < 90% | SNS |
| 🟡 Warning | CPU/JVM > 80% | SNS |
| 🔵 Info | No incoming records | SNS |

## 📈 Dashboard

Acesse o dashboard unificado:
https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=flight-radar-stream-production-streaming-pipeline

### Widgets Incluídos:
1. 📥 Volume de entrada (Kinesis)
2. ⏱️ Backlog de processamento
3. 📊 Throughput em bytes
4. ⚠️ Eventos de throttling
5. ✅/❌ Entregas Firehose (S3 e OpenSearch)
6. ⚡ Métricas Lambda por função
7. 🗄️ Saúde do cluster OpenSearch