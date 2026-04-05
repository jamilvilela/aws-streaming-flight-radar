aws_region   = "us-east-1"
project_name = "flight-radar-stream"
environment  = "production"
datalake_role_name = "role-datalake-analytics"
alerts_email = ["jamilvilela@gmail.com"]

buckets = {
  workspace = "lakehouse-workspace"
  raw       = "lakehouse-raw"
  landing   = "lakehouse-landing"
  trusted   = "lakehouse-trusted"
  business   = "lakehouse-business"
}

databases = {
  landing = "db_landing"
  raw = "db_raw"
  trusted = "db_trusted"
  business = "db_business"
}

tables = {
  tb_opensky_flights = "opensky_flights"
}

###########################################
# AWS Secrets Manager Configuration
# secrets_recovery_window_days = 0
# secrets_log_retention_days   = 7

############################################
# Lambda Functions Configuration
lambda_functions = {
  flights_raw = {
    name              = "flights_raw"
    handler           = "lambda_function.lambda_handler"
    runtime           = "python3.12"
    timeout           = 60
    memory_size       = 512
    ephemeral_storage = 512
    tags = {
      Type   = "raw-ingest"
      Source = "opensky-api"
    }
  }
  flights_enriched = {
    name              = "flights_enriched"
    handler           = "lambda_function.lambda_handler"
    runtime           = "python3.12"
    timeout           = 60
    memory_size       = 512
    ephemeral_storage = 512
    tags = {
      Type   = "enriched-ingest"
      Source = "opensky-api"
    }
  }
}

##############################################
# Kinesis Streams e Firehose Configuration
kinesis_streams = {
  flights_raw = {
    name = "flight-radar-stream-flights-raw"
    mode ="ON_DEMAND"
  }
}

opensearch = {
  flights = {
    collection_name = "flight-radar-flights"
    collection_type = "TIMESERIES"
    standby_replicas = "ENABLED"
    vpc_id = ""  # público 
  }
}


kinesis_firehose = {
  flights_enriched = {
    name                = "flight-radar-firehose-flights-enriched"
    prefix              = "opensky/enriched-flights/"
    error_output_prefix = "opensky/enriched-flights-errors/"
    opensearch_index_name  = "flight-radar-flights"
  }
}


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
  kinesis_iterator_age_ms          = 60000    # 60 segundos
  kinesis_no_records_minutes       = 10
  kinesis_write_throttle_percent   = 5
  kinesis_read_throttle_percent    = 5
  firehose_delivery_failure_percent = 10
  firehose_incoming_records_low    = 1
  lambda_error_percent             = 5
  lambda_duration_p95_ms           = 5000
  lambda_throttle_count            = 10
  opensearch_cpu_percent           = 80
  opensearch_jvm_memory_percent    = 85
  opensearch_indexing_failures     = 5
}

alarm_evaluation_periods = 2
alarm_period_seconds     = 300

