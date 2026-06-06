aws_region         = "us-east-1"
project_name       = "flight-radar-stream"
environment        = "production"
datalake_role_name = "role-datalake-analytics"
alerts_email       = ["jamilvilela@gmail.com"]

buckets = {
  workspace = "lakehouse-workspace"
  raw       = "lakehouse-raw"
  landing   = "lakehouse-landing"
  trusted   = "lakehouse-trusted"
  business  = "lakehouse-business"
}

databases = {
  landing  = "db_landing"
  raw      = "db_raw"
  trusted  = "db_trusted"
  business = "db_business"
}

tables = {
  tb_opensky_flights = "opensky_flights"
}

############################################
# Lambda Functions Configuration
lambda_functions = {
  flights_raw = {
    name              = "flights_raw"
    handler           = "lambda_function.lambda_handler"
    runtime           = "python3.12"
    timeout           = 30
    memory_size       = 512
    ephemeral_storage = 512
    tags = {
      Type   = "raw-ingest"
      Source = "api-gateway-edge"
    }
  }
}

##############################################
# Kinesis Streams
kinesis_streams = {
  flights = {
    name = "flight-radar-stream-flights"
    mode = "ON_DEMAND"
  }
}

################################################
# API Gateway configuration
create_api_gateway                  = true
create_api_key                      = true
api_gateway_stage_name              = "v1"
api_throttle_burst_limit            = 200
api_throttle_rate_limit             = 100
api_quota_limit                     = 100000
lambda_flights_reserved_concurrency = 50

################################################
tags = {
  Environment = "production"
  Project     = "flight-radar-stream"
  ManagedBy   = "terraform"
}


# =============================================================================
# CLOUDWATCH MONITORING
# =============================================================================
alarm_thresholds = {
  kinesis_iterator_age_ms           = 60000
  kinesis_no_records_minutes        = 10
  kinesis_write_throttle_percent    = 5
  kinesis_read_throttle_percent     = 5
  firehose_delivery_failure_percent = 10
  firehose_incoming_records_low     = 1
  lambda_error_percent              = 5
  lambda_duration_p95_ms            = 5000
  lambda_throttle_count             = 10
  opensearch_cpu_percent            = 80
  opensearch_jvm_memory_percent     = 85
  opensearch_indexing_failures      = 5
}

alarm_evaluation_periods = 2
alarm_period_seconds     = 300
