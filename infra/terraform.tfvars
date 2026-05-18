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

kinesis_streams = {
  flights = {
    name = "flight-radar-stream-flights"
    mode = "ON_DEMAND"
  }
  flights_rt = {
    name = "flight-radar-stream-flights-rt"
    mode = "ON_DEMAND"
  }
  flights_positions_1min = {
    name = "flight-radar-stream-flights-positions-1min"
    mode = "ON_DEMAND"
  }
  flights_altitude_bands = {
    name = "flight-radar-stream-flights-altitude-bands"
    mode = "ON_DEMAND"
  }
  flights_phase_changes = {
    name = "flight-radar-stream-flights-phase-changes"
    mode = "ON_DEMAND"
  }
  flights_enriched_raw = {
    name = "flight-radar-stream-flights-enriched-raw"
    mode = "ON_DEMAND"
  }
}

kinesis_firehose = {
  flights = {
    name                = "flight-radar-firehose-flights"
    prefix              = "opensky/flights/"
    error_output_prefix = "opensky/flights-error/"
  }
}

tags = {
  Environment = "production"
  Project     = "flight-radar-stream"
  ManagedBy   = "terraform"
}

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