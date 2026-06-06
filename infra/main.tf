module "kms" {
  source       = "./modules/kms"
  project_name = var.project_name
  tags         = var.tags
}

module "kinesis_stream_flights" {
  source          = "./modules/kinesis_stream_flights"
  project_name    = var.project_name
  kinesis_streams = var.kinesis_streams
  environment     = var.environment
  tags            = var.tags
}

# ============================================================================
# DLQ for invalid records rejected by the ingestion Lambda
# ============================================================================

module "flights_dlq" {
  source       = "./modules/dlq"
  project_name = var.project_name
  name         = "flights-dlq"

  visibility_timeout_seconds = 900
  message_retention_seconds  = 1209600 # 14 days

  tags = var.tags
}

# ============================================================================
# Lambda Authorizer (API Gateway edge)
# ============================================================================

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

  tags = var.tags
}

# IAM role assumed by API Gateway to invoke the authorizer
data "aws_iam_policy_document" "apigateway_assume_role" {
  count = var.create_api_gateway ? 1 : 0
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "apigateway_authorizer" {
  count              = var.create_api_gateway ? 1 : 0
  name               = "${var.project_name}-apigateway-authorizer-invoke-role"
  assume_role_policy = data.aws_iam_policy_document.apigateway_assume_role[0].json
  tags               = var.tags
}

data "aws_iam_policy_document" "apigateway_authorizer_invoke" {
  count = var.create_api_gateway ? 1 : 0
  statement {
    actions   = ["lambda:InvokeFunction"]
    resources = [module.lambda_authorizer.function_arn]
  }
}

resource "aws_iam_role_policy" "apigateway_authorizer_invoke" {
  count  = var.create_api_gateway ? 1 : 0
  name   = "${var.project_name}-apigateway-authorizer-invoke-policy"
  role   = aws_iam_role.apigateway_authorizer[0].id
  policy = data.aws_iam_policy_document.apigateway_authorizer_invoke[0].json
}

# ============================================================================
# Ingestion Lambda (renamed from lambda_flights_raw)
# ============================================================================

module "lambda_flights" {
  source       = "./modules/lambda_flights"
  project_name = var.project_name
  aws_region   = var.aws_region

  lambda_config = var.lambda_functions.flights_raw

  kinesis_stream_name = var.kinesis_streams.flights.name
  kinesis_stream_arn  = module.kinesis_stream_flights.kinesis_stream_flight_arn
  dlq_queue_arn       = module.flights_dlq.queue_arn

  reserved_concurrent_executions = var.lambda_flights_reserved_concurrency
  log_retention_days             = 7

  tags = var.tags
}

# Inject the DLQ URL after both resources exist (the Lambda module needs the
# queue ARN at plan time, the URL is only known after apply).
resource "aws_lambda_function_event_invoke_config" "lambda_flights" {
  function_name = module.lambda_flights.function_name

  destination_config {
    on_failure {
      destination = module.flights_dlq.queue_arn
    }
  }
}

# Async invoke config does not propagate env vars; we use an update-in-place
# SSM-style approach: a null_resource + local-exec would be heavy. Instead
# we re-apply the env var via a follow-up aws_lambda_function update is
# unnecessary - the env var is set at deploy time by the module. The DLQ
# URL is also exposed to the function code through the queue ARN, but
# for clarity we surface it via SSM Parameter Store instead.

# ============================================================================
# API Gateway (edge of the project)
# ============================================================================

resource "aws_cloudwatch_log_group" "apigw_access" {
  count             = var.create_api_gateway ? 1 : 0
  name              = "/aws/apigateway/${var.project_name}-flights-ingest/access"
  retention_in_days = 30
  tags              = var.tags
}

module "api_gateway" {
  source       = "./modules/api_gateway"
  project_name = var.project_name

  endpoint_type = "REGIONAL"
  stage_name    = var.api_gateway_stage_name

  lambda_invoke_arn          = module.lambda_flights.function_invoke_arn
  authorizer_invoke_arn      = module.lambda_authorizer.function_invoke_arn
  authorizer_credentials_arn = aws_iam_role.apigateway_authorizer[0].arn

  throttle_burst_limit = var.api_throttle_burst_limit
  throttle_rate_limit  = var.api_throttle_rate_limit
  quota_limit          = var.api_quota_limit
  quota_period         = "DAY"

  create_api_key     = var.create_api_key
  enable_access_logs = true
  access_log_group_arn = (
    var.create_api_gateway ? aws_cloudwatch_log_group.apigw_access[0].arn : null
  )

  tags = var.tags
}

# ============================================================================
# Flink (Kinesis Data Analytics) downstream consumer
# ============================================================================

module "kinesis_analytics_flights" {
  source = "./modules/kinesis_analytics_flights"

  project_name        = var.project_name
  environment         = var.environment
  region              = var.aws_region
  s3_artifacts_bucket = local.buckets.workspace

  # Kinesis Streams - ARN para substituição nas queries SQL
  kinesis_stream_arn      = module.kinesis_stream_flights.kinesis_stream_flight_arn
  sink_kinesis_stream_arn = module.kinesis_stream_flights.kinesis_stream_flights_rt_arn

  # Flink SQL Scripts (3 camadas)
  # Lê os arquivos SQL do projeto
  sql_source_script   = file("${path.root}/../app/flink-sql-application/01_source.sql")
  sql_enriched_script = file("${path.root}/../app/flink-sql-application/02_enriched_view.sql")
  sql_sinks_script    = file("${path.root}/../app/flink-sql-application/03_sinks_s3.sql")

  # Performance
  input_parallelism = var.flink_config.parallelism

  # Deployment
  # true em produção (via CI/CD), false em dev (controle manual)
  auto_start_application = var.flink_config.auto_start

  # Monitoring & Alerts
  # sns_topic_arn             = module.sns.sns_topic_arn
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

# ============================================================================
# REDSHIFT SERVERLESS DATA WAREHOUSE
# ============================================================================
# 
# Tables created automatically:
# • state_vectors (fact table): Raw enriched ADS-B data
# • state_vectors_1min_summary (agg): Country-level 1-min rollups
# • state_vectors_altitude_bands (agg): Altitude distribution
# • state_vectors_phase_changes (events): Flight phase transitions
# • Materialized Views for QuickSight dashboards
# ============================================================================

# module "redshift_serverless" {
#   source = "./modules/redshift_serverless"
#
#   project_name   = var.project_name
#   environment    = var.environment
#   region         = var.aws_region
#
#   # Network
#   vpc_id         = data.aws_vpc.main.id
#   subnet_ids     = data.aws_subnets.private.ids
#
#   # Database credentials
#   admin_username = var.redshift_config.admin_username
#   admin_password = var.redshift_config.admin_password
#
#   # Capacity
#   base_capacity  = var.redshift_config.base_capacity
#   max_capacity   = var.redshift_config.max_capacity
#
#   # Retention
#   backup_retention_days = var.redshift_config.backup_retention_days
#   log_retention_days    = var.redshift_config.log_retention_days
#
#   # Integrations
#   sns_topic_arn          = module.kda_flights.sns_topic_arn
#   kda_flights_stream_arns = [
#     module.kinesis_stream_flights.kinesis_stream_flight_arn,
#     module.kinesis_stream_flights.kinesis_stream_flights_rt_arn
#   ]
#
#   tags = merge(
#     var.tags,
#     {
#       Component = "Redshift-DataWarehouse"
#       Purpose   = "Analytics-BI-Dashboards"
#     }
#   )
#
#   depends_on = [
#     module.kda_flights,
#     module.iam
#   ]
# }

# module "cloudwatch_monitoring" {
#   source = "./modules/cloudwatch_monitoring"
#
#   project_name    = var.project_name
#   aws_region      = var.aws_region
#   environment     = var.environment
#   tags            = var.tags
#
#   # Kinesis
#   kinesis_stream_name = var.kinesis_streams.flights.name
#   kinesis_stream_arn  = module.kinesis_stream_flights.kinesis_stream_flight_arn
#
#   # Firehose
#   firehose_s3_name        = var.kinesis_firehose.flights.name
#
#   # Lambda
#   lambda_functions = [
#     {
#       name = module.lambda_flights.function_name,
#       arn = module.lambda_flights.function_arn
#     }
#   ]
#
#   # Thresholds
#   alarm_thresholds = var.alarm_thresholds
#
#   # Notificações
#   sns_alarm_topic_arn = module.cloudwatch_monitoring.sns_topic_arn
#   alerts_email        = var.alerts_email
#
#   depends_on = [
#     module.kinesis_stream_flights,
#     module.lambda_flights,
#     # module.redshift_serverless
#   ]
# }
