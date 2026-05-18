module "kms" {
  source       = "./modules/kms"
  project_name = var.project_name
  tags         = var.tags
}

# ============================================================================
# SNS TOPIC FOR KDA ALERTS & NOTIFICATIONS
# ============================================================================
# Centralized notification hub for all pipeline alerts
# Supports: Email, SQS, Lambda for custom processing
# ============================================================================

# module "sns" {
#   source = "./modules/sns"

#   project_name          = var.project_name
#   environment           = var.environment
#   alert_email_addresses = var.sns_config.alert_email_addresses

#   allow_kda_publish                = true
#   enable_delivery_status_logging   = false
#   create_publish_failure_alarm     = true

#   tags = var.tags
# }

# module "api-gateway" {
#   source       = "./modules/api_gateway"
#   project_name = var.project_name
#   tags         = var.tags  
# }

module "kinesis_stream_flights" {
  source          = "./modules/kinesis_stream_flights"
  project_name    = var.project_name
  kinesis_streams = var.kinesis_streams
  environment     = var.environment
  tags            = var.tags
}

module "lambda_flights_raw" {
  source         = "./modules/lambda_flights_raw"
  project_name   = var.project_name
  aws_region     = var.aws_region
  lambda_config  = var.lambda_functions.flights_raw
  kinesis_stream = var.kinesis_streams.flights
  tags           = var.tags
  role_arn       = module.iam.lambda_execution_role_arn
  depends_on = [
    module.iam,
    module.kinesis_stream_flights
  ]
}

module "lambda_flights_enriched" {
  source           = "./modules/lambda_flights_enriched"
  project_name     = var.project_name
  aws_region       = var.aws_region
  lambda_config    = var.lambda_functions.flights_enriched
  kinesis_firehose = var.kinesis_firehose.flights
  role_arn         = module.iam.lambda_execution_role_arn
  tags             = var.tags
  depends_on = [
    module.iam
  ]
}

module "kinesis_firehose_flights" {
  source       = "./modules/kinesis_firehose_flights"
  project_name = var.project_name

  kinesis_stream_arn = module.kinesis_stream_flights.kinesis_stream_flight_arn
  kinesis_firehose   = var.kinesis_firehose.flights
  bucket_arn         = data.aws_s3_bucket.landing.arn
  role_arn           = module.iam.firehose_role_arn
  # lambda_arn          = module.lambda_flights_enriched.lambda_arn

  environment = var.environment
  tags        = var.tags
}

module "kinesis_analytics_flights" {
  source = "./modules/kinesis_analytics_flights"

  project_name        = var.project_name
  environment         = var.environment
  region              = var.aws_region
  s3_artifacts_bucket = local.buckets.workspace

  # IAM Role para Flink
  role_arn = module.iam.kda_execution_role_arn

  # Kinesis Streams
  source_kinesis_stream_arn = module.kinesis_stream_flights.kinesis_stream_flight_arn
  sink_kinesis_stream_arn   = module.kinesis_stream_flights.kinesis_stream_flights_rt_arn

  # Flink SQL Scripts (3 camadas)
  # Lê os arquivos SQL do projeto
  sql_source_script   = file("${path.root}/../app/flink-sql-application/01_source.sql")
  sql_enriched_script = file("${path.root}/../app/flink-sql-application/02_enriched_view.sql")
  sql_sinks_script    = file("${path.root}/../app/flink-sql-application/03_sinks_kinesis.sql")

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
    module.iam,
    # module.sns
  ]
}

# ============================================================================
# REDSHIFT SERVERLESS DATA WAREHOUSE
# ============================================================================
# Receives enriched flight data from KDA Flink
# Provides SQL analytics interface for QuickSight/BI tools
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

#   project_name   = var.project_name
#   environment    = var.environment
#   region         = var.aws_region

#   # Network
#   vpc_id         = data.aws_vpc.main.id
#   subnet_ids     = data.aws_subnets.private.ids

#   # Database credentials
#   admin_username = var.redshift_config.admin_username
#   admin_password = var.redshift_config.admin_password

#   # Capacity
#   base_capacity  = var.redshift_config.base_capacity
#   max_capacity   = var.redshift_config.max_capacity

#   # Retention
#   backup_retention_days = var.redshift_config.backup_retention_days
#   log_retention_days    = var.redshift_config.log_retention_days

#   # Integrations
#   sns_topic_arn          = module.kda_flights.sns_topic_arn
#   kda_flights_stream_arns = [
#     module.kinesis_stream_flights.kinesis_stream_flight_arn,
#     module.kinesis_stream_flights.kinesis_stream_flights_rt_arn
#   ]

#   tags = merge(
#     var.tags,
#     {
#       Component = "Redshift-DataWarehouse"
#       Purpose   = "Analytics-BI-Dashboards"
#     }
#   )

#   depends_on = [
#     module.kda_flights,
#     module.iam
#   ]
# }

# module "cloudwatch_monitoring" {
#   source = "./modules/cloudwatch_monitoring"

#   project_name    = var.project_name
#   aws_region      = var.aws_region
#   environment     = var.environment
#   tags            = var.tags

#   # Kinesis
#   kinesis_stream_name = var.kinesis_streams.flights.name
#   kinesis_stream_arn  = module.kinesis_stream_flights.kinesis_stream_flight_arn

#   # Firehose
#   firehose_s3_name        = var.kinesis_firehose.flights.name

#   # Lambda
#   lambda_functions = [
#     { 
#       name = module.lambda_flights_raw.lambda_name, 
#       arn = module.lambda_flights_raw.lambda_arn 
#     },
#     { 
#       name = module.lambda_flights_enriched.lambda_name, 
#       arn = module.lambda_flights_enriched.lambda_arn 
#     }
#   ]

#   # Thresholds
#   alarm_thresholds = var.alarm_thresholds

#   # Notificações
#   sns_alarm_topic_arn = module.cloudwatch_monitoring.sns_topic_arn
#   alerts_email        = var.alerts_email

#   depends_on = [
#     module.kinesis_stream_flights,
#     module.kinesis_firehose_flights,
#     module.lambda_flights_raw,
#     module.lambda_flights_enriched,
#     # module.redshift_serverless
#   ]
# }

module "iam" {
  source         = "./modules/iam"
  project_name   = var.project_name
  tags           = var.tags
  bucket_arn     = data.aws_s3_bucket.landing.arn
  dash_user_arns = local.dash_user_arns
}

