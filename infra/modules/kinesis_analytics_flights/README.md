# 🚀 Módulo KDA Flights - AWS Kinesis Data Analytics (Apache Flink)

## 🎯 IMPLEMENTAÇÃO: FLINK SQL (Recomendado)

**A partir de Abril de 2026, a implementação usa Flink SQL ao invés de Java.**

Veja [`app/flink-sql-application/`](../../app/flink-sql-application/) para:
- **Arquitetura de 3 camadas**: ingestão → transformação → 4 sinks
- **SQL Scripts**: `01_source.sql`, `02_enriched_view.sql`, `03_sinks_kinesis.sql`
- **Quick Start**: guia de início rápido em `QUICK_START.md`
- **Deploy Script**: `deploy_flink_sql.sh` para automatizar

**Benefícios do SQL:**
✓ Mais legível e mantível  
✓ Sem compilação/deploy de JAR  
✓ Suporte nativo a windowing (TUMBLE, HOP)  
✓ Conversão automática de tipos  

---

## 📋 Descrição

Este módulo Terraform provisiona uma aplicação **Apache Flink** no **AWS Kinesis Data Analytics V2** para processar em tempo real dados de voos provenientes do OpenSky API.

### Fluxo de Processamento

```
kinesis_stream_flights (dados brutos)
    ↓
Apache Flink (KDA)
    ├─ Enriquecimento com dados referenciais
    ├─ Limpeza e validação
    ├─ Agregações em tempo real
    └─ Formatação para consumo Redshift
    ↓
kinesis_stream_flights_rt (dados enriquecidos)
    ↓
Redshift Warehouse → QuickSight (BI)
```

---

## 🔧 Variáveis Terraform

### Obrigatórias
- `project_name`: Nome do projeto
- `role_arn`: ARN da role IAM para KDA
- `source_kinesis_stream_arn`: ARN do stream de entrada (raw)
- `sink_kinesis_stream_arn`: ARN do stream de saída (rt)
- `sql_source_script`: Conteúdo do script `01_source.sql`
- `sql_enriched_script`: Conteúdo do script `02_enriched_view.sql`
- `sql_sinks_script`: Conteúdo do script `03_sinks_kinesis.sql`

### Opcionais
- `environment`: `production` (padrão)
- `region`: `us-east-1` (padrão)
- `input_parallelism`: Paralelismo de entrada em KPUs (padrão: 1)
- `auto_start_application`: Auto-iniciar aplicação (padrão: false)
- `tags`: Map de tags customizadas

### Deprecated (Removidos - Usavam Java/JAR)
- `flink_jar_bucket_arn`: Não usada em SQL
- `flink_jar_key`: Não usada em SQL
- `reference_data_bucket_arn`: Não usada em SQL
- `reference_data_key`: Não usada em SQL

---

## 📦 Schema de Input (Kinesis Source)

A aplicação Flink espera eventos JSON com a seguinte estrutura:

```json
{
  "icao24": "string",
  "callsign": "string",
  "origin_country": "string",
  "time_position": "timestamp",
  "last_contact": "timestamp",
  "longitude": "double",
  "latitude": "double",
  "altitude": "double",
  "on_ground": "boolean",
  "velocity": "double",
  "track": "double",
  "vertical_rate": "double",
  "sensors": "string",
  "geo_altitude": "double",
  "squawk": "string",
  "spi": "boolean",
  "position_source": "integer",
  "category": "string"
}
```

---

##  Implementação: Flink SQL (Recomendado)

**A aplicação agora usa Flink SQL ao invés de Java/JAR.**

### Vantagens
- ✅ Sem compilação - SQL declarativo
- ✅ Windowing nativo - TUMBLE, HOP, SESSION
- ✅ Type safety automática
- ✅ Otimizador de plano de execução
- ✅ Fácil de manter e debugar

### Scripts SQL (3 Camadas)

Veja [`app/flink-sql-application/`](../../app/flink-sql-application/):
1. **01_source.sql** - TABLE SOURCE (consome Kinesis raw)
2. **02_enriched_view.sql** - VIEW enriquecida (conversões + classificações)
3. **03_sinks_kinesis.sql** - 4 Sinks de saída (para Redshift)

---

## 🚀 Deploy com Terraform

### Exemplo: terraform.tfvars

```hcl
project_name              = "flight-radar"
environment               = "production"
input_parallelism         = 4
auto_start_application    = true  # Produção: true (CI/CD), Dev: false (manual)
```

### Deploy Local (Desenvolvimento)

```bash
# 1. Aplica Terraform (sem iniciar Flink)
terraform apply -var="auto_start_application=false"

# 2. Inicia via bash script
bash app/flink-sql-application/deploy_flink_sql.sh start

# 3. Verifica status
bash app/flink-sql-application/deploy_flink_sql.sh logs
```

### Deploy Produção (CI/CD)

```bash
# Developer: apenas faz commit
git push main

# GitHub Actions: 
#   terraform apply -var="auto_start_application=true"
#   → Cria aplicação E inicia automaticamente
```

---

## 📊 Monitoramento

### CloudWatch Logs
- Logs da aplicação: `/aws/kinesisanalytics/flight-radar-kda-flights`
- Stream: `FlinkApplicationLogs`

### Métricas CloudWatch
- `KDA_INPUT_RECORDS_PER_SECOND`: Taxa de eventos de entrada
- `KDA_OUTPUT_RECORDS_PER_SECOND`: Taxa de eventos enriquecidos
- `KDA_ERRORS`: Erros de processamento

### Exemplos de Queries CloudWatch Insights

```
fields @timestamp, @message, @duration
| filter @message like /ERROR/
| stats count() as error_count by @message
```

---

## 🔄 Snapshots para Disaster Recovery

O módulo cria automaticamente snapshots da aplicação Flink:

```bash
# Listar snapshots
aws kinesisanalytics describe-application-snapshots \
  --application-name flight-radar-kda-flights

# Recuperar de um snapshot
aws kinesisanalytics create-application-from-snapshot \
  --snapshot-name flight-radar-kda-flights-snapshot-2026-04-19
```

---

## ⚠️ Notas Importantes

1. **SQL Scripts**: Os 3 arquivos SQL devem existir em `app/flink-sql-application/` e serem passados como strings ao módulo
2. **IAM Permissions**: Certifique-se que a role IAM tem permissões para:
   - Ler de Kinesis Streams
   - Escrever em Kinesis Streams
   - Escrever logs no CloudWatch
3. **Custos**: KDA é cobrado por DPU (Data Processing Unit). Monitorar uso regularmente
4. **Latência**: Esperado ~500ms-2s de latência fim-a-fim (incluindo processamento + rede)
5. **Auto-start**:
   - **Desenvolvimento**: `auto_start_application = false` (você controla via bash)
   - **Produção**: `auto_start_application = true` (GitHub Actions automático)

---

## 📚 Referências

- [AWS KDA Apache Flink](https://docs.aws.amazon.com/kinesis/latest/dev/getting-started-flink.html)
- [Apache Flink Documentation](https://nightlies.apache.org/flink/flink-docs-stable/)
- [Flink SQL Cookbook](https://github.com/ververica/flink-sql-cookbook)
