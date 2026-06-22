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
    name              = "flights-raw"
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
# Aurora Serverless v2 PostgreSQL Configuration
# =============================================================================
# NOTA: Aurora Serverless v2 usa engine_mode="provisioned" com serverlessv2_scaling_configuration.
# O armazenamento é gerenciado automaticamente pelo Aurora (não há allocated_storage).
# A replicação lógica (pglogical) é configurada no cluster parameter group para DMS CDC.
# =============================================================================
# =============================================================================

aurora_config = {
  vpc_id              = "vpc-022139f6bee3cbdd5"
  subnet_ids          = ["subnet-0051cb2e25a8a1cd7", "subnet-060fa607df99778da", "subnet-0033d0f717071e145"]
  allowed_cidr_blocks = ["0.0.0.0/0"]
  db_name             = "flightradar"
  admin_username      = "dbadmin"
  admin_password      = ""  # override via RDS_ADMIN_PASSWORD in .env

  # Aurora Serverless v2 scaling: 0.5 ACU (min) - 8 ACU (max)
  serverless_min_capacity = 0.5
  serverless_max_capacity = 8

  backup_retention_days = 7
  publicly_accessible   = true
  snapshot_identifier   = null
  skip_final_snapshot   = false
  deletion_protection   = false
  reader_count                = 0  # 0 = apenas writer (mais econômico)
  auto_minor_version_upgrade = true
}

################################################
# DMS Serverless Configuration
# DMS Serverless gerencia o compute automaticamente — sem necessidade de
# escolher classe de instância ou armazenamento.
# min_capacity_units=1 / max_capacity_units=4 para full-load-and-cdc.
dms_config = {
  enabled            = true
  min_capacity_units = 1
  max_capacity_units = 4
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


