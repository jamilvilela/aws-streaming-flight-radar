# --------------------------------------------------------------------------- #
# Shared Python Lambda layer (pydantic, boto3, requests, python-dotenv).
# Built from app/layers/python by `setup-env.sh` (or `pip install -r
# app/requirements.txt -t app/layers/python`).
# Lambda layers for Python expect the deps under a top-level `python/`
# directory inside the zip, so we archive the parent (`app/layers/`) and
# let the `python/` subdir be the entry point. The zip itself lives in
# .terraform/ so it isn't accidentally committed.
# Attach the layer to a Lambda via module.python_layer.arn.
# --------------------------------------------------------------------------- #
module "python_layer" {
  source = "./modules/lambda_layer"

  project_name = var.project_name
  layer_name   = "python"
  source_dir   = "${path.root}/../app/layers"
  output_path  = "${path.root}/.terraform/python_layer.zip"
}

module "kinesis_stream_flights" {
  source          = "./modules/kinesis_stream_flights"
  project_name    = var.project_name
  kinesis_streams = var.kinesis_streams
  environment     = var.environment
  tags            = var.tags
}

module "flights_dlq" {
  source       = "./modules/sqs_dlq"
  project_name = var.project_name
  name         = "flights-dlq"

  visibility_timeout_seconds = 900
  message_retention_seconds  = 1209600 # 14 days

  tags = var.tags
}

module "lambda_authorizer" {
  source       = "./modules/lambda_authorizer"
  project_name = var.project_name
  aws_region   = var.aws_region

  lambda_config = {
    name              = "flights-authorizer"
    handler           = "lambda_function.lambda_handler"
    runtime           = "python3.12"
    timeout           = 10
    memory_size       = 256
    ephemeral_storage = 512
  }

  environment_variables = {
    LOG_LEVEL = "INFO"
  }

  layer_arns = [module.python_layer.arn]

  tags = var.tags
}

module "lambda_flights" {
  source       = "./modules/lambda_flights"
  project_name = var.project_name
  aws_region   = var.aws_region

  lambda_config = var.lambda_functions.flights_raw

  kinesis_stream_name = var.kinesis_streams.flights.name
  kinesis_stream_arn  = module.kinesis_stream_flights.kinesis_stream_flight_arn
  dlq_queue_arn       = module.flights_dlq.queue_arn
  dlq_queue_url       = module.flights_dlq.queue_url

  create_api_gateway        = var.create_api_gateway
  api_gateway_execution_arn = module.api_gateway.execution_arn
  layer_arns                = [module.python_layer.arn]

  reserved_concurrent_executions = var.lambda_flights_reserved_concurrency
  log_retention_days             = 7

  tags = var.tags
}

module "api_gateway" {
  source       = "./modules/api_gateway"
  project_name = var.project_name
  api_name     = "flights-api"

  create_api_gateway = var.create_api_gateway
  endpoint_type      = "REGIONAL"
  stage_name         = var.api_gateway_stage_name

  lambda_invoke_arn       = module.lambda_flights.function_invoke_arn
  authorizer_invoke_arn   = module.lambda_authorizer.function_invoke_arn
  authorizer_function_arn = module.lambda_authorizer.function_arn

  throttle_burst_limit      = var.api_throttle_burst_limit
  throttle_rate_limit       = var.api_throttle_rate_limit
  quota_limit               = var.api_quota_limit
  quota_period              = "DAY"
  create_api_key            = var.create_api_key
  enable_access_logs        = true
  access_log_retention_days = 30

  tags = var.tags
}

module "rds_postgres" {
  source = "./modules/rds_postgres"

  project_name = var.project_name
  environment  = var.environment

  vpc_id              = var.rds_config.vpc_id
  subnet_ids          = var.rds_config.subnet_ids
  allowed_cidr_blocks = var.rds_config.allowed_cidr_blocks
  db_name             = var.rds_config.db_name
  admin_username      = var.rds_config.admin_username
  admin_password      = var.rds_admin_password != null ? var.rds_admin_password : var.rds_config.admin_password
  instance_class      = var.rds_config.instance_class

  snapshot_identifier      = var.rds_snapshot_identifier != null ? var.rds_snapshot_identifier : var.rds_config.snapshot_identifier
  read_replicas            = var.rds_config.read_replicas
  allocated_storage_gb     = var.rds_config.allocated_storage_gb
  max_allocated_storage_gb = var.rds_config.max_allocated_storage_gb
  backup_retention_days    = var.rds_config.backup_retention_days
  publicly_accessible      = var.rds_config.publicly_accessible
  skip_final_snapshot      = var.rds_config.skip_final_snapshot
  deletion_protection      = var.rds_config.deletion_protection
  log_retention_days       = var.rds_config.log_retention_days

  tags = var.tags
}

module "dms" {
  count  = var.dms_config.enabled ? 1 : 0
  source = "./modules/dms"

  project_name = var.project_name
  environment  = var.environment
  region       = var.aws_region

  vpc_id              = var.rds_config.vpc_id
  subnet_ids          = var.rds_config.subnet_ids
  rds_security_group_id = module.rds_postgres.security_group_id

  rds_endpoint = module.rds_postgres.db_endpoint
  rds_port     = module.rds_postgres.db_port
  rds_db_name  = module.rds_postgres.db_name

  landing_bucket_name          = local.buckets.landing
  replication_instance_class   = var.dms_config.replication_instance_class
  replication_storage_gb       = var.dms_config.replication_storage_gb
  replication_engine_version   = var.dms_config.engine_version
  dms_task_settings            = var.dms_config.dms_task_settings
  table_mappings               = var.dms_config.table_mappings != null ? var.dms_config.table_mappings : jsonencode({
    rules = [
      {
        rule_type     = "selection"
        rule_id       = "1"
        rule_name     = "flight_radar_aircraft"
        object_locator = {
          schema_name = module.rds_postgres.rds_db_name
          table_name  = "aircraft"
        }
        rule_action   = "include"
      },
      {
        rule_type     = "selection"
        rule_id       = "2"
        rule_name     = "flight_radar_airports"
        object_locator = {
          schema_name = module.rds_postgres.rds_db_name
          table_name  = "airports"
        }
        rule_action   = "include"
      },
      {
        rule_type     = "selection"
        rule_id       = "3"
        rule_name     = "flight_radar_airlines"
        object_locator = {
          schema_name = module.rds_postgres.rds_db_name
          table_name  = "airlines"
        }
        rule_action   = "include"
      },
      {
        rule_type     = "selection"
        rule_id       = "4"
        rule_name     = "flight_radar_flights"
        object_locator = {
          schema_name = module.rds_postgres.rds_db_name
          table_name  = "flights"
        }
        rule_action   = "include"
      },
      {
        rule_type     = "selection"
        rule_id       = "5"
        rule_name     = "flight_radar_positions"
        object_locator = {
          schema_name = module.rds_postgres.rds_db_name
          table_name  = "aircraft_positions"
        }
        rule_action   = "include"
      },
      {
        rule_type     = "selection"
        rule_id       = "6"
        rule_name     = "exclude_dms_control"
        object_locator = {
          schema_name = "dms_control"
          table_name  = "%"
        }
        rule_action   = "exclude"
      }
    ]
  })

  log_retention_days = 7
  tags               = var.tags

  depends_on = [
    module.rds_postgres
  ]
}

module "kinesis_analytics_flights" {
  source = "./modules/kinesis_analytics_flights"

  project_name        = var.project_name
  environment         = var.environment
  region              = var.aws_region
  s3_artifacts_bucket = local.buckets.workspace
  s3_landing_bucket   = local.buckets.landing

  kinesis_stream_arn      = module.kinesis_stream_flights.kinesis_stream_flight_arn
  sink_kinesis_stream_arn = module.kinesis_stream_flights.kinesis_stream_flights_rt_arn

  sql_source_script   = file("${path.root}/../app/flink-sql-application/01_source.sql")
  sql_enriched_script = file("${path.root}/../app/flink-sql-application/02_enriched_view.sql")
  sql_sinks_script    = file("${path.root}/../app/flink-sql-application/03_sinks_s3.sql")

  input_parallelism = var.flink_config.parallelism

  auto_start_application = var.flink_config.auto_start

  create_cloudwatch_alarms = true
  log_retention_days       = 7

  tags = merge(
    var.tags,
    {
      Component = "KDA-Flink"
      Purpose   = "Stream-Processing-Enrichment"
    }
  )

  depends_on = [
    module.kinesis_stream_flights,
  ]
}
