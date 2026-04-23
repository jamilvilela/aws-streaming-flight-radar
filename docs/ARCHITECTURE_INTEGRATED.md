# 🏗️ AWS Streaming Flight Radar - Arquitetura Integrada

**Data**: Abril 21, 2026  
**Status**: ✅ Infraestrutura Completa - Pronta para Deploy  
**Version**: 1.0 (KDA Flink 1.19 + Redshift Serverless)

---

## 📊 Visão Geral da Arquitetura

```
┌─────────────────────────────────────────────────────────────────┐
│                    DATA INGESTION LAYER                         │
├─────────────────────────────────────────────────────────────────┤
│  OpenSky API  ─→  Lambda (flights-raw) ─→  Kinesis Stream       │
│                      (JSON parsing)        (flights-raw)        │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│              STREAM PROCESSING LAYER (KDA Flink)               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Input:  Kinesis Stream "flights-raw" (16-column ADS-B schema)  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────┐       │
│  │  01_source.sql: CREATE TABLE state_vectors_source   │       │
│  │  • WATERMARK 30s (late-event tolerance)             │       │
│  │  • Checkpoint to S3 every 60s (exactly-once)        │       │
│  └────────────────┬─────────────────────────────────────┘       │
│                   │                                              │
│  ┌────────────────▼─────────────────────────────────────┐       │
│  │  02_enriched_view.sql: Transformations              │       │
│  │  • altitude_m → altitude_ft × 3.28084               │       │
│  │  • velocity_m_s → velocity_kts × 1.94384            │       │
│  │  • vertical_rate_m_s → vrate_fpm × 196.85           │       │
│  │  • flight_phase classification (CLIMB/CRUISE/DESC)  │       │
│  │  • vertical_trend (CLIMBING/DESCENDING/LEVEL)       │       │
│  │  • speed_category (GROUND/SLOW/NORMAL/FAST)         │       │
│  └────────────────┬─────────────────────────────────────┘       │
│                   │                                              │
│  ┌────────────────▼─────────────────────────────────────┐       │
│  │  03_sinks_kinesis.sql: 4 Output Streams             │       │
│  │                                                      │       │
│  │  • Sink A: positions-1min                           │       │
│  │    └─→ TUMBLE(1min) GROUP BY country, flight_phase  │       │
│  │    └─→ ~100-300 records/min                         │       │
│  │                                                      │       │
│  │  • Sink B: altitude-bands                           │       │
│  │    └─→ TUMBLE(1min) GROUP BY phase, altitude_band   │       │
│  │    └─→ ~500-1k records/min                          │       │
│  │                                                      │       │
│  │  • Sink C: phase-changes                            │       │
│  │    └─→ TUMBLE(30s) WHERE |vrate_fpm| > 500          │       │
│  │    └─→ ~100-500 records/min (events only)           │       │
│  │                                                      │       │
│  │  • Sink D: enriched-raw                             │       │
│  │    └─→ Passthrough (no aggregation)                 │       │
│  │    └─→ ~50-100k records/min (raw data)              │       │
│  └──────────────────────────────────────────────────────┘       │
│                                                                  │
│  Monitoring:                                                     │
│  • 6 CloudWatch Alarms (crash, checkpoints, latency, etc)       │
│  • Metrics: IncomingRecords, OutgoingRecords, uptime            │
│  • Logs: /aws/kinesisanalytics/flight-radar-kda-flights         │
│  • Notifications: SNS Topic (flight-radar-kda-alerts)           │
└────────┬──────────────────────────────────────────────┬─────────┘
         │                                              │
         ▼                                              ▼
    [Kinesis Streams]                          [SNS Topic: Alerts]
         │                                              │
         ├─→ positions-1min                            ▼
         ├─→ altitude-bands                    [Email Subscribers]
         ├─→ phase-changes
         └─→ enriched-raw
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│           DATA WAREHOUSE LAYER (Redshift Serverless)            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Database: flightradar                                           │
│  Schema: flight_radar                                            │
│                                                                  │
│  ┌─── FACT TABLES ────────────────────────────────────┐         │
│  │                                                    │         │
│  │  state_vectors (100k+ records/min)                 │         │
│  │  ├─ Columns: icao24, callsign, lat, lng, altitude  │         │
│  │  ├─ Enrichments: flight_phase, vertical_trend      │         │
│  │  ├─ Index: timestamp, icao24, lat/lng             │         │
│  │  └─ Retention: 90 days (configurable)             │         │
│  │                                                    │         │
│  └────────────────────────────────────────────────────┘         │
│                                                                  │
│  ┌─── AGGREGATION TABLES ─────────────────────────────┐         │
│  │                                                    │         │
│  │  state_vectors_1min_summary (300/min)              │         │
│  │  ├─ GROUP BY: country, flight_phase, time         │         │
│  │  ├─ Metrics: avg_altitude, avg_velocity, counts   │         │
│  │  └─ Use: Country-level dashboards                 │         │
│  │                                                    │         │
│  │  state_vectors_altitude_bands (1k/min)            │         │
│  │  ├─ GROUP BY: altitude_band, flight_phase, time   │         │
│  │  ├─ Metrics: density, speed distribution          │         │
│  │  └─ Use: Airspace congestion analysis             │         │
│  │                                                    │         │
│  │  state_vectors_phase_changes (500/min)            │         │
│  │  ├─ FILTER: vertical_trend changed, high vrate    │         │
│  │  ├─ Metrics: aircraft ID, phase transition        │         │
│  │  └─ Use: Anomaly detection, SLA monitoring        │         │
│  │                                                    │         │
│  └────────────────────────────────────────────────────┘         │
│                                                                  │
│  ┌─── MATERIALIZED VIEWS ─────────────────────────────┐         │
│  │                                                    │         │
│  │  mv_active_aircraft_summary                        │         │
│  │  └─→ Total active, by phase, countries, metrics   │         │
│  │                                                    │         │
│  │  mv_top_countries                                  │         │
│  │  └─→ Top 50 countries by aircraft count            │         │
│  │                                                    │         │
│  │  mv_recent_phase_changes                           │         │
│  │  └─→ Last 30 min of significant movements          │         │
│  │                                                    │         │
│  └────────────────────────────────────────────────────┘         │
│                                                                  │
│  Capacity:                                                       │
│  • Base: 32 RPUs (Redshift Processing Units)                    │
│  • Max: 256 RPUs (auto-scaling)                                 │
│  • Backup: 7 days (configurable)                               │
│  • Network: Private subnets, VPC Endpoints                      │
│  • Encryption: At-rest (KMS), in-transit (TLS)                 │
│                                                                  │
│  IAM Permissions:                                                │
│  • Read: S3, KMS, Kinesis (for data loading)                   │
│  • Write: CloudWatch Logs, Metrics                             │
│  • Access: SNS (alerts from KDA)                               │
│                                                                  │
└────────┬──────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│              ANALYTICS & VISUALIZATION LAYER                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  QuickSight Dashboards (connected to Redshift)                  │
│  ├─ Real-time active aircraft map                              │
│  ├─ Country-level traffic distribution                         │
│  ├─ Altitude band heatmaps                                     │
│  ├─ Phase transitions timeline                                 │
│  └─ SLA/anomaly detection charts                               │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔐 Segurança e Monitoramento

### CloudWatch Alarms (6 Alarmes)

| Alarme | Métrica | Threshold | Ação |
|--------|---------|-----------|------|
| 🔴 **Failed Checkpoints** | numberOfFailedCheckpoints | > 0 / 5min | SNS → Email |
| 🔴 **Job Crash** | uptime | = 0 / 1min | SNS → Email (CRITICAL) |
| 🟡 **No Input Data** | IncomingRecords | < 100 / 5min | SNS → Email |
| 🔴 **Task Failures** | numberOfRecordsFailed | > 10 / 5min | SNS → Email |
| 🟡 **No Output** | OutgoingRecords | < 50 / 5min | SNS → Email |
| 🟡 **High Latency** | millisBehindLatest | > 60s | SNS → Email |

### SNS Topic

**Nome**: `flight-radar-kda-alerts`

**Subscriptions** (configurar após deploy):
```bash
# Email subscription
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:ACCOUNT_ID:flight-radar-kda-alerts \
  --protocol email \
  --notification-endpoint ops@company.com

# Setup interativo
bash scripts/setup_kda_alerts.sh
```

### Logs & Tracing

| Serviço | Log Group | Retention |
|---------|-----------|-----------|
| KDA Flink | `/aws/kinesisanalytics/flight-radar-kda-flights` | 7 dias |
| Redshift | `/aws/redshift-serverless/flight-radar` | 7 dias |
| Alarms | CloudWatch Metrics (custom) | -∞ |

---

## 📁 Estrutura de Módulos Terraform

```
infra/
├── main.tf                          # Orquestração de módulos
├── variables.tf                     # Variáveis globais
├── data.tf                          # Data sources (VPC, subnets, etc)
├── locals.tf                        # Locals (computed values)
├── providers.tf                     # Provider configuration
├── outputs.tf                       # Outputs
├── terraform.tfstate                # State file
├── terraform.tfstate.backup         # State backup
├── tfplan                           # Plan file
│
├── modules/
│   ├── kms/                         # KMS Key Management
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── iam/                         # IAM Roles & Policies
│   │   ├── data.tf                  # Policy documents
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   └── variables.tf
│   │
│   ├── kinesis_stream_flights/      # Kinesis Streams
│   │   ├── data.tf
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   └── variables.tf
│   │
│   ├── kinesis_firehose_flights/    # Kinesis Firehose → S3
│   │   ├── data.tf
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   └── variables.tf
│   │
│   ├── lambda_flights_raw/          # Lambda (OpenSky → Kinesis)
│   │   ├── data.tf
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   └── variables.tf
│   │
│   ├── lambda_flights_enriched/     # Lambda (Kinesis → Firehose)
│   │   ├── data.tf
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   └── variables.tf
│   │
│   ├── kda_flights/                 # KDA Flink SQL Application ⭐
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── data.tf
│   │   ├── alarms.tf                # CloudWatch Alarms + SNS
│   │   ├── ddl_setup.tf             # DDL execution (post-deploy)
│   │   └── README.md
│   │
│   ├── redshift_serverless/         # Redshift Serverless ⭐ NEW
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── data.tf
│   │   ├── ddl_setup.tf             # DDL execution (post-deploy)
│   │   ├── ddl.sql                  # Schema SQL
│   │   ├── README.md
│   │   └── [New] Materialized views, indexes
│   │
│   └── cloudwatch_monitoring/       # CloudWatch (legacy)
│       ├── data.tf
│       ├── main.tf
│       ├── outputs.tf
│       └── variables.tf
│
├── tfvars/
│   └── terraform.tfvars             # Variable values
│
└── .terraform/                      # Terraform internals
```

---

## 🚀 Fluxo de Dados Detalhado

### 1️⃣ **Ingestão de Dados**

```
OpenSky API (flightdata.opensky-network.org)
    ↓ (every 10 seconds)
Lambda: flights-raw
    • Parse JSON (ADS-B format)
    • Extract 16 columns
    • Put to Kinesis stream "flights-raw"
    ↓
Kinesis Stream: flights-raw (ON_DEMAND)
    • Shard: 1 (auto-scaled as needed)
    • Retention: 24 hours
    • Cardinality: ~30-50k records/min
```

### 2️⃣ **Stream Processing (Flink)**

```
Kinesis Stream: flights-raw
    ↓
[KDA Flink Application]
    ├─ 01_source.sql
    │   ├─ CREATE TABLE state_vectors_source
    │   ├─ Columns: icao24, callsign, origin_country, ...
    │   └─ WATERMARK FOR event_time AS event_time - INTERVAL '30' SECOND
    │
    ├─ 02_enriched_view.sql
    │   ├─ CREATE VIEW enriched_flights
    │   ├─ Unit conversions (altitude, velocity, vrate)
    │   ├─ Classifications (flight_phase, vertical_trend, speed_category)
    │   └─ Result: enriched data ready for multiple sinks
    │
    └─ 03_sinks_kinesis.sql
        ├─ INSERT INTO positions-1min
        │   └─ TUMBLE(1min) GROUP BY country, flight_phase
        ├─ INSERT INTO altitude-bands
        │   └─ TUMBLE(1min) GROUP BY phase, altitude_band
        ├─ INSERT INTO phase-changes
        │   └─ TUMBLE(30s) WHERE vertical_trend changed
        └─ INSERT INTO enriched-raw
            └─ Passthrough (all data)
    
State Management:
    • Checkpoints: S3 (every 60 seconds)
    • Checkpoint policy: EXACTLY_ONCE
    • State retention: Infinite (for recovery)
    
Monitoring:
    • Metrics: IncomingRecords, OutgoingRecords, uptime
    • Alarms: 6 CloudWatch alarms (SNS notifications)
    • Logs: /aws/kinesisanalytics/flight-radar-kda-flights
```

### 3️⃣ **Data Loading to Redshift**

```
Kinesis Sinks (4 streams)
    ├─ positions-1min (~300/min)
    ├─ altitude-bands (~1k/min)
    ├─ phase-changes (~500/min)
    └─ enriched-raw (~100k/min)
    
    ↓ [Kinesis Firehose - TO DO: Create module]
    
S3 Buffer (optional, for batching)
    └─ S3://flight-radar-${ACCOUNT}-trusted/kda-output/
    
    ↓ (JDBC or Firehose connection)
    
Redshift Serverless
    ├─ flight_radar.state_vectors
    ├─ flight_radar.state_vectors_1min_summary
    ├─ flight_radar.state_vectors_altitude_bands
    ├─ flight_radar.state_vectors_phase_changes
    ├─ flight_radar.mv_active_aircraft_summary
    ├─ flight_radar.mv_top_countries
    └─ flight_radar.mv_recent_phase_changes
```

### 4️⃣ **Analytics & Reporting**

```
Redshift Materialized Views
    ↓
QuickSight Dashboards
    ├─ Real-time active aircraft
    ├─ Country distribution
    ├─ Altitude bands
    ├─ Phase transitions
    └─ Anomalies (SLA violations)

Email Reports (scheduled)
    ├─ Daily: Top countries, top routes
    ├─ Weekly: Trends, growth metrics
    └─ On-demand: Ad-hoc queries
```

---

## 📊 Data Model

### Fact Table: `state_vectors`

```sql
icao24 VARCHAR(8)                  -- Aircraft identifier
callsign VARCHAR(8)                -- Flight number
origin_country VARCHAR(64)         -- Departure country
longitude DOUBLE PRECISION         -- Position
latitude DOUBLE PRECISION          -- Position
altitude_ft DOUBLE PRECISION       -- Altitude (enriched from meters)
velocity_kts DOUBLE PRECISION      -- Speed (enriched from m/s)
vertical_rate_fpm DOUBLE PRECISION -- Climb/descent rate (enriched)
true_track DOUBLE PRECISION        -- Heading
flight_phase VARCHAR(16)           -- CRUISE, CLIMB, DESCENT, LEVEL, GROUND
vertical_trend VARCHAR(16)         -- CLIMBING, DESCENDING, LEVEL, GROUND
speed_category VARCHAR(16)         -- GROUND, SLOW, NORMAL, FAST, SUPERSONIC
event_timestamp_utc TIMESTAMP      -- When the data point occurred
ingestion_timestamp TIMESTAMP      -- When we received it
```

### Aggregation Table: `state_vectors_1min_summary`

```sql
window_start TIMESTAMP            -- 1-min window start
window_end TIMESTAMP              -- 1-min window end
origin_country VARCHAR(64)        -- GROUP BY key
flight_phase VARCHAR(16)          -- GROUP BY key
aircraft_count BIGINT             -- COUNT(DISTINCT icao24)
avg_altitude_ft DOUBLE PRECISION  -- AVG(altitude_ft)
avg_velocity_kts DOUBLE PRECISION -- AVG(velocity_kts)
climbing_count BIGINT             -- COUNT WHERE flight_phase = 'CLIMB'
descending_count BIGINT           -- COUNT WHERE flight_phase = 'DESCENT'
...
```

---

## 🔄 Workflow: Dev → Production

### ✅ Desenvolvimento (Local)

```bash
# 1. Terraform plan (dry-run)
cd infra
terraform plan \
  -var-file=tfvars/terraform.tfvars \
  -var="flink_config.auto_start=false"

# 2. Deploy infrastructure
terraform apply \
  -var-file=tfvars/terraform.tfvars \
  -var="flink_config.auto_start=false"

# 3. Verify KDA created but not started
terraform output kda_application_status
# Output: READY

# 4. Start Flink manually (for testing)
bash app/flink-sql-application/deploy_flink_sql.sh start

# 5. Run data flow tests
python scripts/test_flink_pipeline.py

# 6. Setup SNS subscriptions
bash scripts/setup_kda_alerts.sh

# 7. Stop when done
bash app/flink-sql-application/deploy_flink_sql.sh stop
```

### ✅ Produção (CI/CD)

```bash
# 1. Git commit
git add .
git commit -m "KDA Flink + Redshift: Streaming flight radar"
git push origin main

# 2. GitHub Actions triggers automatically
#    → Job: validate (Terraform format, SQL files)
#    → Job: plan (Terraform plan with var.flink_config.auto_start=true)
#    → Job: approval (manual review)
#    → Job: apply (Terraform apply + auto-start KDA)
#    → Job: test (Python test script)
#    → Job: notify (Email/Slack status)

# 3. KDA starts automatically after apply
#    (var.flink_config.auto_start=true in CI/CD)

# 4. Data flows: OpenSky → Kinesis → KDA → Redshift
#    Monitoring: CloudWatch Alarms → SNS → Email
```

---

## 📈 Performance & Capacity

### Throughput Expectations

| Stage | Records/Min | MB/Min | Notes |
|-------|-------------|--------|-------|
| OpenSky API ingestion | 30-50k | 30-50 | Raw ADS-B data |
| Kinesis flights-raw | 30-50k | 30-50 | 1 shard (ON_DEMAND) |
| KDA Input | 30-50k | 30-50 | Parallelism=1 (4 KPUs) |
| KDA Sink A (1min) | 100-300 | 0.1-0.3 | Aggregated |
| KDA Sink B (altitude) | 500-1k | 0.5-1.0 | Aggregated |
| KDA Sink C (phase) | 100-500 | 0.1-0.5 | Events only |
| KDA Sink D (raw) | 50-100k | 50-100 | Passthrough |
| Redshift Ingestion | ~100k | ~50-100 | Via Firehose |

### Redshift Capacity

```
Base Capacity: 32 RPUs
Max Capacity: 256 RPUs
Auto-scaling: Enabled

Estimated Query Time:
• SELECT * FROM state_vectors: 5-10s (100k rows)
• SELECT ... FROM mv_active_aircraft_summary: <1s (materialized)
• JOIN state_vectors + 1min_summary: 10-20s (depends on date range)
```

---

## 🛠️ Troubleshooting Guide

### Issue: KDA Application Crashes

```bash
# Check status
aws kinesisanalyticsv2 describe-application \
  --application-name flight-radar-kda-flights \
  --query 'ApplicationDetail.ApplicationStatus'

# View last logs
aws logs tail /aws/kinesisanalytics/flight-radar-kda-flights --follow

# Restart from last checkpoint
aws kinesisanalyticsv2 start-application \
  --application-name flight-radar-kda-flights
```

### Issue: No Data in Redshift

```bash
# Check Kinesis source
aws kinesis describe-stream --stream-name flights-raw \
  --query 'StreamDescription.StreamStatus'

# Check KDA output metrics
aws cloudwatch get-metric-statistics \
  --metric-name OutgoingRecords \
  --namespace AWS/Kinesis \
  --dimensions Name=Application,Value=flight-radar-kda-flights \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum

# Verify Redshift connection
psql -h <redshift-endpoint> -U admin -d flightradar \
  -c "SELECT COUNT(*) FROM flight_radar.state_vectors;"
```

### Issue: High Latency (millisBehindLatest > 60s)

```bash
# Increase KDA parallelism
# In Terraform: flink_config.parallelism = 2 or 4

# Or increase Redshift capacity
aws redshiftserverless modify-workgroup \
  --workgroup-name flight-radar-workgroup \
  --config-parameters parameterName=max_query_time,parameterValue=600

# Monitor bottleneck
# • Check KDA CPU/Memory usage
# • Check Kinesis shard metrics
# • Check Redshift query performance
```

---

## 📚 Referências & Documentação

### Dentro do Projeto

- 📖 [KDA_IAM_ALARMS_GUIDE.md](../docs/KDA_IAM_ALARMS_GUIDE.md) - IAM policy + alarms
- 📖 [infra/modules/kda_flights/README.md](./modules/kda_flights/README.md) - KDA Flink details
- 📖 [infra/modules/redshift_serverless/README.md](./modules/redshift_serverless/README.md) - Redshift setup
- 📖 [DEPLOYMENT_STRATEGY.md](../docs/DEPLOYMENT_STRATEGY.md) - Deployment options
- 📖 [GITHUB_ACTIONS_SETUP.md](../docs/GITHUB_ACTIONS_SETUP.md) - CI/CD setup

### AWS Documentation

- [KDA v2 Documentation](https://docs.aws.amazon.com/kinesis/latest/dev/key-concepts.html)
- [Redshift Serverless](https://docs.aws.amazon.com/redshift/latest/mgmt/working-with-serverless.html)
- [Flink SQL Reference](https://nightlies.apache.org/flink/flink-docs-release-1.19/docs/dev/table/sql/overview/)
- [CloudWatch Alarms](https://docs.aws.amazon.com/AmazonCloudWatch/latest/events/WhatIsCloudWatchEvents.html)

---

## ✅ Deployment Checklist

### Pre-Deployment

- [ ] AWS account configured with proper credentials
- [ ] VPC with private subnets in 2+ AZs
- [ ] S3 buckets created (landing, raw, trusted, business)
- [ ] Redshift admin password stored in Secrets Manager
- [ ] GitHub Actions configured with AWS OIDC provider

### Deployment

- [ ] `terraform init` completed
- [ ] `terraform plan` reviewed
- [ ] `terraform apply` succeeded
- [ ] All modules created successfully
- [ ] KDA application in READY state
- [ ] Redshift endpoint accessible

### Post-Deployment

- [ ] KDA started (manual or automatic)
- [ ] Data flowing: OpenSky API → Kinesis
- [ ] Flink processing: Kinesis → 4 sinks
- [ ] Redshift loaded: Data in all 4 tables
- [ ] SNS subscriptions configured (email)
- [ ] Test alarms triggered successfully
- [ ] QuickSight dashboards created
- [ ] Monitoring verified (CloudWatch, logs)

---

## 📞 Support & Escalation

| Issue | Action | Contact |
|-------|--------|---------|
| KDA crashes | Check logs, restart | DevOps team |
| Redshift slow | Monitor metrics, scale up | DB team |
| Data delay > 1min | Increase Flink parallelism | Data eng |
| Missing data | Verify Kinesis → Redshift pipeline | Data eng |
| Access denied | Check IAM policies | Security team |

---

**Document Version**: 1.0  
**Last Updated**: April 21, 2026  
**Status**: ✅ Ready for Production Deployment
