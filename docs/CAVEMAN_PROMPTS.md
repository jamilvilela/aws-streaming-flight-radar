# Caveman Prompts — AWS Streaming Flight Radar

Use esses patterns para comunicação rápida com dev teams.

---

## Python Example: Lambda Ingestion

```
fn lê OpenSky API → dict de voos
+ autenticação OAuth2 w/ Secrets Manager
+ envia batch para Kinesis (PutRecords)
+ retry logic: exponential backoff (2s, 4s, 8s)
+ structured logging (JSON)
+ type hints + pydantic config

! sem hardcode credentials
! sem try/except genérico (catch específico)
✗ evita fazer HTTP síncrono sem timeout
✓ partition key = icao24 (distribuição)

→ retorna: True/False (success/failure)
```

**Corolário**: [app/lambda_flights_raw/src/lambda_function.py](app/lambda_flights_raw/src/lambda_function.py)

---

## SQL Example: Flink Enriquecimento

```
stream: state_vectors_source (Kinesis raw)
  ↓
transformações:
  + conversão unidades (m/s → knots, m → feet)
  + classificação fase voo (ground/takeoff/cruise/landing)
  + validação geoloc (lon -180~180, lat -90~90)
  ↓
window aggregation: TUMBLE(event_time, 1 MINUTE)
  [sink_1] S3 por país + fase: count, avg_alt, avg_vel
  [sink_2] S3 altitude bands: stddev, min/max
  [sink_3] S3 phase changes (stream passthrough)
  [sink_4] S3 metrics (count/nulls/dupes)

+ CTE nomeadas (readable)
+ window functions w/ ROWTIME (não PROCTIME!)
! partition output por dt (yyyy-MM-dd-HH)
! watermark 30s (tolera events fora de ordem)
✗ evita SELECT * (explicit columns)
✗ evita PROCTIME em TUMBLE (wrong timestamp)

→ output: 4 Parquet datasets ~1min latency
```

**Corolário**: [app/flink-sql-application/](app/flink-sql-application/)

---

## Terraform Example: Lambda Module

```
module: lambda_flights_raw @AWS
  ↓
recursos:
  + IAM role: AssumeRole (Lambda service)
  + IAM policy: Secrets Manager (GetSecretValue)
  + IAM policy: Kinesis (PutRecord/PutRecords)
  + IAM policy: CloudWatch Logs
  + Lambda function (handler: lambda_function.lambda_handler)
  + CloudWatch log group (retention: 7 days)

configuração:
  + runtime: Python 3.11
  + timeout: 60s
  + memory: 512 MB
  + ephemeral_storage: 512 MB
  
env variables:
  + KINESIS_STREAM (stream name)
  + OPENSKY_SECRET_ARN (Secrets Manager ARN)
  + LOG_LEVEL (INFO)

! remote state: S3 + DynamoDB lock
! variáveis: não hardcode (use var.*)
! secrets: sensitive = true
✗ evita inline policy (use data + attachment)
✓ usa data.aws_iam_policy_document (cleaner)

→ outputs: lambda_arn, lambda_role_arn
```

**Corolário**: [infra/modules/lambda_flights_raw/](infra/modules/lambda_flights_raw/)

---

## Terraform Example: KDA Module

```
module: kinesis_analytics_flights @AWS
  ↓
recursos:
  + KDA V2 application (runtime: FLINK-1_20)
  + IAM role (Kinesis + S3 + KMS access)
  + CloudWatch log group + log stream
  + S3 objects: Flink SQL zip + JAR connector
  
configuração:
  + mode: STREAMING
  + application_code: ZIP (3 SQL files)
  + checkpoint: DEFAULT (AWS managed)
  + parallelism: custom + auto-scaling
  + restart-strategy: none (Kinesis bug workaround)

environment properties:
  + KINESIS_STREAM_ARN (input stream)
  + AWS_REGION (dynamic)
  + restart-strategy = "none"

! foco: parametrização (não hardcode ARN/región)
! IAM least-privilege: Kinesis + S3 específicos
! KMS: restrict a (kms:ViaService)
✗ evita checkpoint DEFAULT + partial recovery (bug)
✓ usa environment_properties para variables

→ outputs: kda_arn, kda_name
```

**Corolário**: [infra/modules/kinesis_analytics_flights/](infra/modules/kinesis_analytics_flights/)

---

## Architecture Example: Full Pipeline

```
arq: event-driven streaming data lake @AWS
     latência target: < 5 min e2e

┌─────────────────────────────────────────────────┐
│                   OPENSKY API                    │
└──────────────────┬────────────────────────────────┘
                   │ OAuth2
                   ▼
   ┌──────────────────────────────┐
   │  AWS Secrets Manager         │
   │  └─ client_id, secret        │
   └──────────────┬───────────────┘
                  │ GetSecretValue (IAM: ✓)
                  ▼
   ┌──────────────────────────────────┐
   │  Lambda (ingest-flights)         │
   │  ✓ retry logic (backoff)         │
   │  ✓ structured logging           │
   │  + batching: max 500 records     │
   └──────────────┬───────────────────┘
                  │ PutRecords
                  ▼
   ┌──────────────────────────────────┐
   │  Kinesis Streams (ON_DEMAND)     │
   │  flight-radar-stream-flights     │
   │  partition key: icao24           │
   └──────────────┬───────────────────┘
                  │ JSON Records
                  ▼
   ┌──────────────────────────────────┐
   │  KDA / Flink SQL                 │
   │  ✓ parametrizado (ARN, region)   │
   │  ✓ event time: ROWTIME           │
   │  ✓ watermark: 30s                │
   └──────────────┬───────────────────┘
        ┌─────────┼──────────┬──────────┐
        │         │          │          │
        ▼         ▼          ▼          ▼
     Sink_1    Sink_2    Sink_3     Sink_4
     (1min)   (Altitude) (Changes)  (Metrics)
        │         │          │          │
        └─────────┼──────────┼──────────┘
                  │
                  ▼
   ┌──────────────────────────────────────┐
   │  S3 Landing (Parquet)                │
   │  ✓ partitioned: dt (yyyy-MM-dd-HH)   │
   │  ✓ compressão: snappy               │
   │  ✓ schema: inferred + validated       │
   └──────────────────────────────────────┘

custo estimado:
  → Lambda: ~$0.20/1M invocations
  → Kinesis: $0.36/hour (ON_DEMAND)
  → KDA: $0.25/KPU-hour (1 KPU = ~50k events/min)
  → S3: $0.023/GB stored (data lifecycle)
  ────────────────────────────
  ≈ $50-100/mês (dev), $500+/mês (production)

! monitore: Lambda errors, Kinesis age, Flink status
! alarmes: >5 Lambda errors/5min → SNS
```

**Corolário**: [ANALYSIS_VISUAL.md](ANALYSIS_VISUAL.md#-arquitetura-corrigida)

---

## SQL Example: Flink Source → Aggregation

```
TABLE state_vectors_source (Kinesis):
  icao24, callsign, origin_country, time_position,
  altitude, velocity, heading, vertical_rate, on_ground

  ↓ transform (VIEW)
  
  + parse ISO8601 timestamps
  + convert units (m/s→knots, m→feet)
  + classify flight_phase (ground/takeoff/cruise/high)
  + classify vertical_trend (climbing/level/descending)

  ↓ aggregate (TUMBLE)

WINDOW tumble_1min AS TUMBLE(event_time, INTERVAL 1 MINUTE)
GROUP BY origin_country, flight_phase
SELECT:
  TUMBLE_START(event_time) AS window_start
  origin_country
  flight_phase
  COUNT(*) AS aircraft_count
  AVG(altitude_ft) AS avg_altitude_ft
  AVG(velocity_kts) AS avg_velocity_kts
  SUM(CASE on_ground THEN 1 ELSE 0 END) AS on_ground_count

→ OUTPUT: S3 Parquet /flights-positions-1min/

! usar TUMBLE (not HOP): sem overlap
! partition by dt (query pruning)
! watermark: tolera 30s latency
✗ evita SELECT * (overhead)
✓ CTE readable + debuggable
```

**Corolário**: [app/flink-sql-application/03_sinks_s3.sql](app/flink-sql-application/03_sinks_s3.sql)

---

## Error Patterns → Fixes

```
✗ "AccessDenied: secretsmanager"
  → ✓ Check IAM policy (secretsmanager:GetSecretValue)
  
✗ "FileNotFoundError: 03_sinks_kinesis.sql"
  → ✓ Rename file to 03_sinks_s3.sql
  
✗ "Stream ARN not found" (Kinesis)
  → ✓ Parametrize: ${KINESIS_STREAM_ARN} em runtime

✗ "Partial recovery not supported" (Flink)
  → ✓ Set: restart-strategy = "none" em app.py

✗ "ProvisionedThroughputExceededException"
  → ✓ Implement retry w/ exponential backoff (Lambda)

✗ "Windows closing early" (Flink time issue)
  → ✓ Use ROWTIME not PROCTIME
  
✗ "Data loss on Lambda failure"
  → ✓ Implement DLQ (Dead Letter Queue) pattern
```

---

## Performance Patterns

```
Lambda → Kinesis:
  ! batch size: 500 records (API limit)
  ! retry: 3x w/ backoff (2^n seconds)
  ! partition key: even distribution (icao24)
  ? throttle happens? → auto-retry handled

Kinesis → Flink:
  ! event time: use ROWTIME (not PROCTIME)
  ! watermark: 30s (allows out-of-order)
  ! parallelism: 1-4 KPUs (dev), 8-16 KPUs (prod)
  ? data late >30s? → discarded (acceptable)

Flink → S3:
  ! output format: Parquet (80% compression)
  ! partition: by date hour (hourly queries)
  ! commit delay: 1h (batches writes)
  ? small files? → use rolling policies
  
overall latency target: < 5 min e2e
  current: ~2-3 min (good!)
```

---

## Deployment Checklist (Caveman Style)

```
PRE-DEPLOY
[ ] terraform validate      → no syntax errors
[ ] terraform plan -o=tf    → review resources
[ ] Secrets Manager setup   → opensky credentials
[ ] S3 buckets exist        → workspace + landing
[ ] No hardcoded credentials in code
[ ] All SQL files present   → 01_source, 02_view, 03_sinks

DEPLOY
[ ] terraform apply -auto-approve
[ ] Check AWS CloudFormation → stacks created
[ ] Lambda: GetFunction OK
[ ] Kinesis: ListStreams OK
[ ] KDA: DescribeApplication OK

POST-DEPLOY
[ ] Lambda invoke manual     → test run
[ ] CloudWatch Logs check   → no ERROR
[ ] Kinesis records         → count > 0
[ ] Flink job status        → RUNNING
[ ] S3 files               → size > 0
[ ] Performance monitor     → latency < 5min

ALARM SETUP
[ ] Lambda errors > 5/5min → SNS
[ ] Kinesis age > 60s      → SNS
[ ] KDA failed             → SNS
[ ] S3 writes failing      → SNS
```

---

*Prompt patterns | June 5, 2026 | caveman-style*
