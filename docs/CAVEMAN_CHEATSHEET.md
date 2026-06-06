# Caveman Cheatsheet — Copy-Paste Commands

Operações mais comuns, um copy-paste, sem pensar.

---

## 🚀 Deploy

### First Time: Full Setup

```bash
# 1. setup aws credentials
export AWS_PROFILE=dev
export AWS_REGION=us-east-1

# 2. create secrets manager entry
aws secretsmanager create-secret \
  --name opensky-credentials \
  --secret-string '{"client_id":"YOUR_ID","client_secret":"YOUR_SECRET"}'

# 3. get arn for terraform
SECRET_ARN=$(aws secretsmanager describe-secret \
  --secret-id opensky-credentials \
  --query ARN --output text)
echo "SECRET_ARN=$SECRET_ARN"

# 4. create terraform.tfvars
cat > infra/terraform.tfvars << EOF
region                 = "us-east-1"
environment            = "dev"
opensky_secret_arn     = "$SECRET_ARN"
kinesis_stream_name    = "flight-radar-stream-flights"
s3_landing_bucket      = "my-org-flight-data-landing"
s3_workspace_bucket    = "my-org-flight-data-workspace"
EOF

# 5. validate terraform
cd infra
terraform init
terraform fmt -recursive
terraform validate
terraform plan -out=tfplan

# 6. deploy
terraform apply tfplan
```

### Update Code: Redeploy

```bash
# update SQL files
aws s3 cp app/flink-sql-application/ \
  s3://MY_WORKSPACE_BUCKET/flink-sql/ --recursive

# restart KDA (graceful)
aws kinesisanalytics stop-application \
  --application-name flight-radar-flink \
  --force

# wait + restart
sleep 30
aws kinesisanalytics start-application \
  --application-name flight-radar-flink

echo "✓ Redeployed"
```

---

## 🐛 Debug

### Lambda Not Processing?

```bash
# 1. check logs
aws logs tail /aws/lambda/flight-radar-ingest --follow

# 2. check if invoked
aws logs filter-log-events \
  --log-group-name /aws/lambda/flight-radar-ingest \
  --filter-pattern "START" \
  --query 'events[0:5]'

# 3. manual invoke (test)
aws lambda invoke \
  --function-name flight-radar-ingest \
  --log-type Tail \
  --query 'LogResult' \
  --output text | base64 -d

# 4. check IAM (secrets access)
aws iam get-role-policy \
  --role-name flight-radar-lambda-role \
  --policy-name secrets-access

# 5. check secrets
aws secretsmanager get-secret-value \
  --secret-id opensky-credentials \
  --query 'SecretString' | jq .
```

### Kinesis Not Receiving Data?

```bash
# 1. list streams
aws kinesis list-streams

# 2. describe stream
aws kinesis describe-stream \
  --stream-name flight-radar-stream-flights

# 3. get records (check if data flowing)
SHARD_ID=$(aws kinesis describe-stream \
  --stream-name flight-radar-stream-flights \
  --query 'StreamDescription.Shards[0].ShardId' \
  --output text)

SHARD_ITERATOR=$(aws kinesis get-shard-iterator \
  --stream-name flight-radar-stream-flights \
  --shard-id $SHARD_ID \
  --shard-iterator-type LATEST \
  --query 'ShardIterator' \
  --output text)

aws kinesis get-records --shard-iterator $SHARD_ITERATOR

# 4. check metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/Kinesis \
  --metric-name GetRecords.IteratorAgeMilliseconds \
  --dimensions Name=StreamName,Value=flight-radar-stream-flights \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Maximum
```

### Flink Not Outputting to S3?

```bash
# 1. describe app
aws kinesisanalytics describe-application \
  --application-name flight-radar-flink \
  --query 'ApplicationDetail | {Status: ApplicationStatus, LastUpdateTimestamp}'

# 2. check logs
aws logs tail /aws/kinesisanalytics/flight-radar-flink --follow

# 3. restart gracefully
aws kinesisanalytics stop-application \
  --application-name flight-radar-flink
sleep 30
aws kinesisanalytics start-application \
  --application-name flight-radar-flink

# 4. check S3 outputs
aws s3 ls s3://MY_LANDING_BUCKET/ --recursive \
  --human-readable --summarize

# 5. check file age
aws s3api list-objects-v2 \
  --bucket MY_LANDING_BUCKET \
  --query 'Contents | sort_by(@, &LastModified) | [-1]' \
  --output table
```

---

## 📊 Monitoring

### Real-Time Metrics

```bash
# Lambda: errors + duration
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Errors \
  --dimensions Name=FunctionName,Value=flight-radar-ingest \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Sum

# Kinesis: age + throughput
aws cloudwatch get-metric-statistics \
  --namespace AWS/Kinesis \
  --metric-name GetRecords.IteratorAgeMilliseconds \
  --dimensions Name=StreamName,Value=flight-radar-stream-flights \
  --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Maximum

# KDA: lag
aws kinesisanalytics list-applications \
  --query 'ApplicationSummaries[] | [?ApplicationName==`flight-radar-flink`]'
```

### Create Alarm (Email on Error)

```bash
# 1. create SNS topic
SNS_TOPIC=$(aws sns create-topic \
  --name flight-radar-alerts \
  --query 'TopicArn' \
  --output text)

# 2. subscribe email
aws sns subscribe \
  --topic-arn $SNS_TOPIC \
  --protocol email \
  --notification-endpoint "team@example.com"

# 3. create alarm (Lambda errors > 5 in 5min)
aws cloudwatch put-metric-alarm \
  --alarm-name flight-radar-lambda-errors \
  --alarm-actions $SNS_TOPIC \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 300 \
  --threshold 5 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --evaluation-periods 1 \
  --dimensions Name=FunctionName,Value=flight-radar-ingest

echo "✓ Alarm created: $SNS_TOPIC"
```

---

## 🧹 Cleanup

### Destroy All Resources

```bash
cd infra

# 1. plan destruction
terraform plan -destroy -out=tfplan-destroy

# 2. destroy (careful!)
terraform apply tfplan-destroy

# 3. cleanup state
rm -f terraform.tfstate*

echo "✓ All resources destroyed"
```

### Delete Specific Resource

```bash
# example: delete KDA app (not Lambda, to preserve code)
terraform destroy \
  -target 'module.kinesis_analytics_flights.aws_kinesisanalytics_application.flink_app' \
  -auto-approve
```

---

## 📝 Logs

### Tail All Logs (Combined)

```bash
# Lambda + KDA + Kinesis
watch -n 5 'echo "=== Lambda ===" && \
  aws logs tail /aws/lambda/flight-radar-ingest --max-items 10 && \
  echo "" && \
  echo "=== KDA ===" && \
  aws logs tail /aws/kinesisanalytics/flight-radar-flink --max-items 10'
```

### Search for Errors

```bash
# Lambda: errors last hour
aws logs filter-log-events \
  --log-group-name /aws/lambda/flight-radar-ingest \
  --start-time $(($(date +%s%N | cut -b1-13) - 3600000)) \
  --filter-pattern 'ERROR' \
  --query 'events[].message'

# KDA: throttling
aws logs filter-log-events \
  --log-group-name /aws/kinesisanalytics/flight-radar-flink \
  --start-time $(($(date +%s%N | cut -b1-13) - 600000)) \
  --filter-pattern 'Throttled' \
  --query 'events[].message'
```

---

## 💰 Cost Estimation

```bash
# Lambda cost (monthly estimate)
# invocations * $0.20 per 1M
invocations_per_day=86400  # 1 per second
invocations_per_month=$((invocations_per_day * 30))
lambda_cost=$(echo "scale=2; $invocations_per_month * 0.20 / 1000000" | bc)
echo "Lambda/month: \$$lambda_cost"

# Kinesis ON_DEMAND (monthly estimate)
# $0.50 per 1M PUT operations
puts_per_day=$((invocations_per_day * 100))  # 100 records per invocation
puts_per_month=$((puts_per_day * 30))
kinesis_cost=$(echo "scale=2; $puts_per_month * 0.50 / 1000000" | bc)
echo "Kinesis/month: \$$kinesis_cost"

# Total estimate
total=$(echo "scale=2; $lambda_cost + $kinesis_cost" | bc)
echo "Total (dev)/month: \$$total"
```

---

## 🔑 IAM Quick Check

```bash
# List all roles
aws iam list-roles \
  --query 'Roles[] | [?contains(RoleName, `flight-radar`)] | [].RoleName'

# Check Lambda role policies
aws iam list-role-policies \
  --role-name flight-radar-lambda-role

# Check specific policy (inline)
aws iam get-role-policy \
  --role-name flight-radar-lambda-role \
  --policy-name lambda-kinesis-policy

# Check attached policies (managed)
aws iam list-attached-role-policies \
  --role-name flight-radar-lambda-role
```

---

## 🚨 Emergency: Rollback

```bash
# If deployment broke everything:

# 1. stop pipeline (graceful)
aws kinesisanalytics stop-application \
  --application-name flight-radar-flink

# 2. go back to previous Terraform state
cd infra
git log --oneline | head
git checkout HEAD~1 -- .

# 3. re-apply previous version
terraform apply -auto-approve

# 4. manual restart KDA
aws kinesisanalytics start-application \
  --application-name flight-radar-flink

echo "✓ Rolled back to previous version"
```

---

## 🆚 Compare Deployments

```bash
# Compare current state vs. S3 (backup)
aws s3 sync s3://MY_WORKSPACE_BUCKET/backup/flink-sql-last/ ./flink-sql-compare/
diff -r app/flink-sql-application/ flink-sql-compare/

# See what changed in Lambda
aws lambda get-function \
  --function-name flight-radar-ingest \
  --query 'Configuration | {Runtime, Handler, Timeout, MemorySize}' \
  --output table
```

---

*Quick commands | copy-paste ready | caveman-style | June 5, 2026*
