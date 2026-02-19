# control_account = "331504768406"

aws_region   = "us-east-1"
project_name = "flight-radar-stream"
environment  = "production"
datalake_role_name = "role-datalake-analytics"

buckets = {
  workspace = "lakehouse-workspace"
  raw       = "lakehouse-raw"
  landing   = "lakehouse-landing"
  trusted   = "lakehouse-trusted"
  business   = "lakehouse-business"
}
 
###########################################
# AWS Secrets Manager Configuration
secrets_recovery_window_days = 0
secrets_log_retention_days   = 7

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
    # kinesis_stream    = "flight-radar-stream-flights-raw"
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
    # kinesis_stream    = "flight-radar-stream-flights-enriched"
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

kinesis_firehose = {
  flights_enriched = {
    name = "flight-radar-firehose-flights-enriched"
    prefix             = "opensky/enriched-flights/"
    error_output_prefix = "opensky/enriched-flights-errors/"
  }
}

################################################
tags = {
  Environment = "production"
  Project     = "flight-radar-stream"
  ManagedBy   = "terraform"
}