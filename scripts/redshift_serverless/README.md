# Redshift Serverless Module

Módulo Terraform para provisionamento de Redshift Serverless com integração com KDA Flink.

## 📋 Overview

Este módulo cria:
- **Redshift Serverless Namespace** com configurações de backup e logging
- **Redshift Serverless Workgroup** com auto-scaling e network settings
- **IAM Role** com permissões para S3, KMS, CloudWatch
- **Security Group** para acesso ao banco de dados
- **CloudWatch Logs** para auditoria e troubleshooting
- **Redshift DDL Schema** com tabelas otimizadas para dados de KDA Flink

## 🏗️ Arquitetura

```
┌─────────────────────┐
│   KDA Flink         │
│   4 Kinesis Sinks   │
└──────────┬──────────┘
           │ (Kinesis Firehose)
           ▼
┌─────────────────────┐
│   S3 (Buffer)       │ ◄─── Optional staging
└──────────┬──────────┘
           │
           ▼
┌──────────────────────────────┐
│  Redshift Serverless         │
│  • state_vectors (fact)      │
│  • 1min_summary (agg)        │
│  • altitude_bands (agg)      │
│  • phase_changes (events)    │
│  • Materialized Views (mv)   │
└──────────┬───────────────────┘
           │
           ▼
┌─────────────────────┐
│   QuickSight / BI   │
│   (Dashboards)      │
└─────────────────────┘
```

## 📊 Tabelas Criadas

| Tabela | Propósito | Cardinality | Atualização |
|--------|----------|-------------|------------|
| `state_vectors` | Dados brutos enriquecidos | ~100k/min | Contínua |
| `state_vectors_1min_summary` | Agregação por país/fase | ~300/min | 1min |
| `state_vectors_altitude_bands` | Distribuição por altitude | ~1k/min | 1min |
| `state_vectors_phase_changes` | Eventos de transição | ~500/min | 30s |

**Materialized Views** (para QuickSight):
- `mv_active_aircraft_summary` - Resumo de aeronaves ativas
- `mv_top_countries` - Top 50 países por contagem
- `mv_recent_phase_changes` - Transições recentes

## 🔧 Variáveis Requeridas

```hcl
redshift_serverless = {
  admin_password = "SecurePassword123!"  # Min 8 chars, uppercase, lowercase, digit, special
  
  vpc_id = aws_vpc.main.id
  subnet_ids = [
    aws_subnet.private_1a.id,
    aws_subnet.private_1b.id
  ]
}
```

## 🔑 Variáveis Opcionais

```hcl
base_capacity = 32                    # RPUs (Redshift Processing Units)
max_capacity = 512                    # Auto-scaling max
backup_retention_days = 7             # Snapshot retention
log_retention_days = 7                # CloudWatch logs retention
publicly_accessible = false           # Security: keep private
enhanced_vpc_routing = true           # Network security
```

## 📤 Outputs

```hcl
workgroup_endpoint    = "flight-radar-redshift-workgroup.123456789.us-east-1.redshift-serverless.amazonaws.com"
workgroup_port        = 5439
database_name         = "flightradar"
admin_username        = "admin"

# Connection strings (sensitive)
redshift_connection_string  # JDBC for BI tools
redshift_psql_connection    # CLI command
```

## 🚀 Como Usar

### 1. No `infra/main.tf`

```hcl
module "redshift_serverless" {
  source = "./modules/redshift_serverless"

  project_name   = var.project_name
  environment    = var.environment
  region         = var.region
  
  vpc_id         = aws_vpc.main.id
  subnet_ids     = [aws_subnet.private_1a.id, aws_subnet.private_1b.id]
  
  admin_username = var.redshift_admin_username
  admin_password = var.redshift_admin_password
  
  database_name  = "flightradar"
  base_capacity  = 32
  max_capacity   = 256
  
  sns_topic_arn  = module.kda_flights.sns_topic_arn
  
  tags = var.tags
}
```

### 2. Em `infra/terraform.tfvars`

```hcl
redshift_admin_username = "admin"
# Use AWS Secrets Manager para password!
redshift_admin_password = "ChangeMe123!@#"
```

### 3. Deploy

```bash
cd infra
terraform plan
terraform apply

# Outputs
terraform output redshift_connection_string
terraform output redshift_psql_connection
```

### 4. Verificar Criação das Tabelas

```bash
# Get connection string
CONN=$(terraform output -raw redshift_psql_connection)

# Connect and verify
eval "$CONN"
SELECT COUNT(*) FROM flight_radar.state_vectors;
```

## 🔗 Integração com KDA Flink

### Via Kinesis Firehose

Para enviar dados de Kinesis streams do KDA para Redshift:

```hcl
module "kinesis_firehose_to_redshift" {
  source = "./modules/kinesis_firehose_redshift"
  
  firehose_name    = "kda-enriched-to-redshift"
  
  # Source: KDA Flink sinks
  source_stream_arn = module.kda_flights.kinesis_enriched_stream_arn
  
  # Destination: Redshift
  redshift_endpoint = module.redshift_serverless.workgroup_endpoint
  redshift_port     = module.redshift_serverless.workgroup_port
  redshift_database = module.redshift_serverless.database_name
  redshift_table    = "flight_radar.state_vectors"
  
  # Auth
  redshift_role_arn = module.redshift_serverless.iam_role_arn
}
```

### Via Lambda Transformer

Para transformações customizadas:

```hcl
module "lambda_kda_to_redshift" {
  source = "./modules/lambda_kinesis_transformer"
  
  # Lambda receives records from Kinesis
  # Transforms and inserts into Redshift
  
  redshift_connection_string = module.redshift_serverless.redshift_connection_string
}
```

## 📊 QuickSight Integration

### Dashboard Setup

```bash
# 1. Create QuickSight dataset connected to Redshift
#    Data Source: Redshift
#    Host: workgroup_endpoint
#    Port: 5439
#    Database: flightradar
#    Table: flight_radar.mv_active_aircraft_summary

# 2. Create dashboards from materialized views
#    • Active aircraft summary
#    • Top countries map
#    • Phase changes timeline
#    • Altitude distribution chart
```

## 🔐 Security

### IAM Permissions

Redshift tem permissões para:
- ✅ Read S3 objects (data loading)
- ✅ Decrypt S3 with KMS
- ✅ Write CloudWatch logs
- ✅ Put CloudWatch metrics
- ✅ Read SNS topics (from KDA alerts)

### Network Security

- ✅ Private subnets (no internet access)
- ✅ Security group restricting CIDR blocks
- ✅ Enhanced VPC routing enabled
- ✅ No public endpoint by default

### Credential Management

```bash
# Store password in AWS Secrets Manager (RECOMMENDED)
aws secretsmanager create-secret \
  --name redshift/admin-password \
  --secret-string "SecurePassword123!@#"

# Reference in Terraform
data "aws_secretsmanager_secret_version" "redshift_password" {
  secret_id = aws_secretsmanager_secret.redshift.id
}

variable "redshift_admin_password" {
  default = data.aws_secretsmanager_secret_version.redshift_password.secret_string
}
```

## 📈 Performance Tuning

### Distribution Keys

```sql
-- Tables distributed by event timestamp (DISTKEY)
-- Optimizes queries filtering by time range
DISTKEY (event_timestamp_utc)
```

### Sort Keys

```sql
-- Sort keys for common query patterns
SORTKEY (event_timestamp_utc, icao24)
```

### Materialized Views Refresh

```sql
-- Manually refresh (or schedule via AWS Lambda)
REFRESH MATERIALIZED VIEW flight_radar.mv_active_aircraft_summary;
```

## 🛠️ Troubleshooting

### Connection Issues

```bash
# Test connectivity
psql -h <endpoint> -U admin -d flightradar

# Check security group
aws ec2 describe-security-groups \
  --group-ids sg-xxxxx \
  --query 'SecurityGroups[0].IpPermissions'
```

### Query Performance

```sql
-- Check table statistics
SELECT
  schema_name,
  table_name,
  size,
  tbl_rows
FROM svv_table_info
WHERE schema_name = 'flight_radar';

-- Analyze table
ANALYZE flight_radar.state_vectors;
```

### DDL Application Issues

```bash
# Check if schemas/tables exist
\dt flight_radar.*

# View DDL script from SSM Parameter
aws ssm get-parameter \
  --name /flight-radar/redshift/ddl-script \
  --query 'Parameter.Value' \
  --output text
```

## 📚 Referências

- [AWS Redshift Serverless Documentation](https://docs.aws.amazon.com/redshift/latest/mgmt/working-with-serverless.html)
- [Redshift SQL Reference](https://docs.aws.amazon.com/redshift/latest/dg/reference-sql.html)
- [Materialised Views Best Practices](https://docs.aws.amazon.com/redshift/latest/dg/mv-create-materialized-view.html)
- [KDA → Redshift Integration Patterns](https://docs.aws.amazon.com/kinesis/latest/dev/kda-lambda-output.html)

## 📝 Notas de Implementação

- ✅ Redshift Serverless (não precisa provisionar clusters)
- ✅ Auto-scaling baseado em workload (RPUs)
- ✅ Snapshot backup automático
- ✅ Multi-AZ deployment (subnets em AZs diferentes)
- ✅ Encrypted at rest (KMS)
- ✅ VPC endpoint ready (para private S3 access)
- ⚠️ DDL setup requer manual `psql` ou Lambda post-deploy

---

**Última Atualização**: Abril 21, 2026
**Terraform Version**: >= 1.0
**AWS Provider**: >= 5.0
