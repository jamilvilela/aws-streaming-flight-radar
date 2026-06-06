# Caveman Patterns — Real-World Cases

Casos reais + soluções padrão para este projeto.

---

## Case 1: Lambda Falha Silenciosamente

### Sintoma
```
CloudWatch: 
  Lambda executions: 100
  Lambda errors: 0
  
Mas: S3 vazio, Kinesis vazio (zero records)
```

### Debug
```
✗ Check 1: Lambda invocado?
  → CloudWatch Logs / "START RequestId"
  → se não tem: EventBridge/scheduled invocation failing

✓ Fiz: grep "START" lambda-logs
  → achei 100 invocations
  
✗ Fiz 2: Secrets Manager acessível?
  → run: AWS CLI: aws secretsmanager get-secret-value --secret-id opensky
  → se falha: IAM policy missing (iam.tf)

✓ Fiz: policy check → detalhes no CAVEMAN_SUMMARY
  
✗ Fiz 3: HTTP request?
  → CloudWatch Logs: "RequestException" ou "HTTPError"
  → se simples: OpenSky API throttling ou down
```

### Pattern: Silent Failure

```
lambda fn:
  ├─ try/catch genérico (BAD)
  │  └─ swallows all errors
  │
  ├─ structured logging (GOOD)
  │  └─ log EVERY step
  │  └─ nivel: DEBUG > INFO > WARN > ERROR
  │
  └─ metrics cloudwatch
     └─ custom metric: flights_processed
```

**Fix Pattern**:
```python
@log_exceptions  # decorator
def lambda_handler(event, context):
    logger.info(f"START | event={event}")
    
    try:
        secrets = get_secrets()  # log inside
        flights = fetch_opensky()  # log + metric
        send_kinesis(flights)  # log + metric
        logger.info(f"SUCCESS | count={len(flights)}")
        return {"statusCode": 200}
    except ClientError as e:
        logger.error(f"AWS ERROR | {e.response['Error']['Code']}")
        raise  # re-raise = CloudWatch detects
    except Exception as e:
        logger.error(f"UNEXPECTED | {type(e).__name__}: {e}", exc_info=True)
        raise
```

---

## Case 2: Kinesis Throttling (ProvisionedThroughputExceededException)

### Sintoma
```
CloudWatch Lambda:
  ERROR: ProvisionedThroughputExceededException
  → data loss (Lambda timeout 60s → fails)
```

### Pattern: Exponential Backoff Retry

```
retry logic (must be):
  attempt 1: fail → sleep 1s → retry
  attempt 2: fail → sleep 2s → retry
  attempt 3: fail → sleep 4s → final attempt
  attempt 4: fail → return error (Lambda DLQ)

! exponential: 2^n, not linear
+ preserva throughput (not hammering)
+ respects: circuit-breaker pattern
```

**Implementation**:
```python
def put_records_with_retry(kinesis, stream, records, max_retries=3):
    for attempt in range(max_retries):
        try:
            response = kinesis.put_records(
                StreamName=stream,
                Records=records
            )
            if response['FailedRecordCount'] == 0:
                return response
            else:
                # partial failure: retry just failed ones
                failed = [r for r in zip(records, response['Records'])
                         if r[1].get('ErrorCode')]
                records = [r[0] for r in failed]
                raise ClientError({'Error': {'Code': 'PartialFailure'}})
        except ClientError as e:
            code = e.response['Error']['Code']
            if code == 'ProvisionedThroughputExceededException' and attempt < max_retries - 1:
                sleep_time = 2 ** attempt
                logger.warning(f"Throttled, retry in {sleep_time}s")
                time.sleep(sleep_time)
            else:
                raise
    return None
```

---

## Case 3: Flink Job Stuck (No Output to S3)

### Symptom
```
KDA console: Job Status = RUNNING (green)
Flink taskmanager logs: normal
S3 bucket: empty (or stale files)
```

### Debug Checklist
```
✗ 1. Is source Kinesis receiving data?
   → AWS CLI: aws kinesis get-records --stream-name flight-radar-stream-flights
   → check: ShardIterator returns records? Yes → data flowing

✓ 2. Is app getting watermark?
   → Flink metrics: "Current watermark" > 0?
   → check: Task Managers > Metrics
   
✗ 3. Are windows firing?
   → Flink logs: "Triggered window [start,end]"
   → check: grep "Triggered" in logs
   
✗ 4. Is sink writing?
   → Flink logs: "Writing batch to S3"
   → check: grep "S3" in logs
   
✓ 5. Is IAM role correct?
   → Error logs: "AccessDenied" or "NoSuchBucket"?
   → check: iam.tf (KDA role + policies)
```

### Common Root Causes

```
cause 1: PROCTIME vs ROWTIME (wrong timestamp)
  → symptom: windows never fire
  → fix: use CURRENT_TIMESTAMP AS event_time ROWTIME
  
cause 2: Watermark too aggressive
  → symptom: data discarded immediately
  → fix: adjust: WATERMARK FOR event_time AS event_time - INTERVAL '30' SECOND
  
cause 3: Sink bucket/path wrong
  → symptom: logs say "bucket not found"
  → fix: verify ${SINK_BUCKET} is set in env properties
  
cause 4: S3 IAM policy missing
  → symptom: logs say "AccessDenied"
  → fix: verify s3:PutObject + s3:GetObject in KDA role
  
cause 5: Parallelism too low
  → symptom: lag increasing (CPU 100%)
  → fix: increase KPUs or tune parallelism
```

---

## Case 4: Data Quality Issues (Bad Records in S3)

### Symptoms
```
S3 Parquet files corrupt
OR data values wrong (nulls, negative values)
OR missing columns
```

### Validation Pattern

```
flink SQL: add transformations to filter/validate

+ add CASE/WHEN for type conversions
+ add WHERE clauses for validation
+ add CAST for type safety
+ log rejected records (metrics)

before sink:
  ├─ altitude_ft > 0?  (validate)
  ├─ latitude -90..90? (validate)
  ├─ velocity_kts >= 0? (validate)
  └─ if fail: send to error_sink (DLQ pattern)
```

**SQL Pattern**:
```sql
CREATE VIEW enriched_validated AS
SELECT
  icao24,
  callsign,
  CAST(altitude AS FLOAT) AS altitude_ft,
  CASE 
    WHEN altitude < -500 THEN NULL  -- invalid
    WHEN altitude > 50000 THEN NULL -- unlikely
    ELSE altitude
  END AS altitude_ft_validated,
  event_time,
  ROW_NUMBER() OVER (PARTITION BY icao24 ORDER BY event_time DESC) AS rn
FROM enriched
WHERE
  latitude >= -90 AND latitude <= 90
  AND longitude >= -180 AND longitude <= 180
  AND velocity_kts >= 0;

-- sink valid
INSERT INTO s3_valid_flights
SELECT * FROM enriched_validated WHERE rn = 1;

-- send invalid to DLQ (debug)
INSERT INTO dlq_invalid_records
SELECT
  CURRENT_TIMESTAMP,
  'altitude_out_of_range' AS error_reason,
  *
FROM enriched
WHERE altitude < -500 OR altitude > 50000;
```

---

## Case 5: Cost Overrun (Bill Spike)

### Symptom
```
AWS Billing:
  Last month: $50
  This month: $500 (10x!)
```

### Investigate Cost

```
breakdown:
  → Kinesis: charged per shard-hour
    if ON_DEMAND: cost is per PUT operation
    ? overrun cause: millions of PutRecords?
    
  → KDA: charged per KPU-hour
    if scaled 1 KPU → 8 KPUs: cost 8x
    ? overrun cause: auto-scaling triggered?
    
  → S3: charged per GB stored + requests
    ? overrun cause: huge files + no lifecycle?
    
  → Lambda: charged per invocation + duration
    ? overrun cause: many retries?
```

### Fix Pattern

```
✓ Kinesis ON_DEMAND:
  → best for variable load
  → pay per write: $0.50 per 1M PUT ops
  → cost = requests * 0.0000005

✗ Kinesis PROVISIONED (if switching):
  → fixed per shard-hour
  → for predictable load only
  → cost = shards * 0.36 * hours

KDA cost optimization:
  → set parallelism low (dev: 1, prod: 4)
  → avoid auto-scaling (manual better)
  → check: is job actually processing?
  
S3 cost optimization:
  → lifecycle rule: delete old partitions (30 days)
  → enable: intelligent-tiering
  → compress: Parquet + snappy already good
```

---

## Case 6: Debugging Flink Errors (Cryptic Messages)

### Common Errors

```
✗ ERROR: "ClassNotFoundException: org.apache.flink.connector.kinesis.FlinkKinesisConsumer"
  → cause: JAR not loaded
  → fix: check S3 has kinesis-connector JAR
  
✗ ERROR: "Malformed arn"
  → cause: ${KINESIS_STREAM_ARN} not substituted
  → fix: verify app.py replaces placeholders
  
✗ ERROR: "Task attempt timed out"
  → cause: processing too slow or stuck
  → fix: increase timeout in Job Manager config
  
✗ ERROR: "Restore failed: checkpoint data missing"
  → cause: S3 checkpoint bucket deleted/moved
  → fix: start fresh (from beginning), use restart-strategy=none

✗ ERROR: "Partition assignment for topic failed"
  → cause: Kinesis permissions issue
  → fix: verify IAM role has kinesis:ListShards, kinesis:GetRecords
```

---

## Case 7: Deploying Updates (No Downtime)

### Pattern: Blue-Green

```
approach 1: duplicate infrastructure
  step 1: deploy KDA v2 (new SQL)
  step 2: run in parallel (both reading Kinesis)
  step 3: compare outputs
  step 4: switch traffic
  step 5: delete old KDA

approach 2: in-place upgrade (simpler)
  step 1: stop KDA job
  step 2: update SQL files in S3
  step 3: restart KDA job
  → downtime: ~2 min
  → acceptable for dev/test

recommended (this project):
  → approach 2 (in-place)
  → for prod: use blue-green (no downtime)
```

**Deployment Script**:
```bash
#!/bin/bash

# Update Flink SQL files
aws s3 cp app/flink-sql-application/ s3://${FLINK_BUCKET}/app/ --recursive

# Stop current job (graceful)
aws kinesisanalytics stop-application \
  --application-name flight-radar-flink \
  --force

# Wait for stop
sleep 30

# Start job (will resume from checkpoint)
aws kinesisanalytics start-application \
  --application-name flight-radar-flink

echo "Deploy complete, job restarting..."
```

---

## Case 8: Performance Tuning

### Metrics to Watch

```
Lambda:
  + Duration: aim < 30s (not 60s)
  + Error rate: aim < 0.1%
  + Throttles: if > 0 → scale Lambda concurrency
  → CloudWatch metric: "Duration" + "Errors"

Kinesis:
  + Age of oldest record: aim < 1h (fresh data)
  + Iterator age: aim < 5 min
  + Get operations: monitor for spikes
  → AWS Metric: GetRecords, PutRecords

Flink:
  + Processing latency: aim < 5 min e2e
  + Watermark: should advance (not stuck)
  + Checkpoint duration: should be < 30s
  + Back pressure: if high → scale KPUs up
  → Flink Metrics: "currentProcessingTime", "watermark"

S3:
  + File count: growing? (good)
  + Object size: ~100MB per file (tunable)
  + Latency: new file appears in < 5min
```

### Tuning Knobs

```
if Lambda slow:
  ✓ increase memory (more CPU)
  ✓ reduce batch size (OpenSky API)
  ✗ don't increase timeout > 60s (wastes $)

if Kinesis throttled:
  ✓ use ON_DEMAND (dynamic scaling)
  ✓ batch records smarter (reduce PutRecords calls)
  ✗ don't go PROVISIONED (high fixed cost)

if Flink slow:
  ✓ increase parallelism (KPUs)
  ✓ reduce window size (1min → 30s)
  ✓ add more memory per task
  ✗ don't increase checkpoint interval (defeats purpose)

if S3 cost high:
  ✓ add lifecycle: delete files > 30 days
  ✓ enable intelligent-tiering
  ✓ batch writes (increase checkpoint delay)
```

---

## Case 9: Disaster Recovery

### Backup Strategies

```
scenario 1: Lambda code corrupted
  recovery: git rollback + redeploy
  RTO: 5 min
  RPO: 0 (code versioned)

scenario 2: Kinesis data lost
  recovery: re-run Lambda for period
  → manual invoke: aws lambda invoke --payload '{"start": "2026-01-01"}' ...
  RTO: 30 min
  RPO: depends on API rate limits

scenario 3: Flink job failed
  recovery: KDA auto-restart (or manual start)
  → automatic: enabled by default
  RTO: 2 min
  RPO: checkpoint recovery (few min of data max)

scenario 4: S3 bucket deleted
  recovery: restore from backup (if versioning enabled)
  → terraform doesn't enable by default
  ! ENABLE versioning on S3 bucket (production)
  RTO: 1 hour
  RPO: depends on version history
```

### Disaster Recovery Checklist

```
[ ] Terraform state backed up (S3 + DynamoDB lock)
[ ] Lambda code in git + tagged releases
[ ] Secrets Manager backed up (manual)
[ ] S3 bucket versioning enabled
[ ] CloudWatch logs retention > 30 days
[ ] Flink checkpoint retention > 24h
[ ] Alerting configured (Lambda errors, Kinesis age)
[ ] Runbook created: how to recover from each failure
[ ] Recovery tested: monthly drill
```

---

## Case 10: Production Hardening Checklist

```
security:
  [ ] IAM roles: least-privilege (not *)
  [ ] Secrets: encrypted (KMS)
  [ ] S3: private (no public read)
  [ ] Kinesis: encrypted (KMS)
  [ ] VPC: private subnets for Lambda (if on VPC)

resilience:
  [ ] Lambda: retry logic + DLQ
  [ ] Kinesis: ON_DEMAND (or provisioned + ASG)
  [ ] Flink: checkpoint enabled + retention 24h+
  [ ] S3: versioning + lifecycle policies

observability:
  [ ] CloudWatch: logs + metrics for all components
  [ ] Alarms: errors, throttles, age
  [ ] Dashboard: real-time status
  [ ] Tracing: X-Ray enabled (optional)

compliance:
  [ ] Audit logs: CloudTrail enabled
  [ ] Data retention: clear policy
  [ ] Encryption: in-transit + at-rest
  [ ] Access: tagged/documented (who/why)
```

---

*Real-world patterns | caveman debug guide | June 5, 2026*
