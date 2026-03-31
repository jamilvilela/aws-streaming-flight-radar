module "iam" {
  source       = "./modules/iam"
  project_name = var.project_name
  tags         = var.tags
  bucket_arn = data.aws_s3_bucket.landing.arn
  # opensearch_domain_name = var.opensearch.flights.domain_name
}

module "kms" {
  source       = "./modules/kms"
  project_name = var.project_name
  tags         = var.tags
}

# module "api-gateway" {
#   source       = "./modules/api_gateway"
#   project_name = var.project_name
#   tags         = var.tags  
# }

module "kinesis_stream_flights_raw" {
  source     = "./modules/kinesis_stream_flights_raw"
  project_name    = var.project_name
  kinesis_stream  = var.kinesis_streams.flights_raw
  environment     = var.environment
  tags            = var.tags
}

module "lambda_flights_raw" {
  source              = "./modules/lambda_flights_raw"
  project_name        = var.project_name
  aws_region          = var.aws_region
  lambda_config       = var.lambda_functions.flights_raw
  kinesis_stream      = var.kinesis_streams.flights_raw
  tags                = var.tags
  role_arn            = module.iam.lambda_execution_role_arn
  depends_on = [ 
    module.iam, 
    module.kinesis_stream_flights_raw 
  ]
}

module "lambda_flights_enriched" {
  source              = "./modules/lambda_flights_enriched"
  project_name        = var.project_name
  aws_region          = var.aws_region 
  lambda_config       = var.lambda_functions.flights_enriched
  kinesis_firehose    = var.kinesis_firehose.flights_enriched
  role_arn            = module.iam.lambda_execution_role_arn
  tags                = var.tags
  depends_on = [ 
    module.iam
  ]
}


module "opensearch" {
  source            = "./modules/opensearch"
  project_name      = var.project_name
  environment       = var.environment
  collection_name   = var.opensearch.flights.collection_name
  collection_type   = var.opensearch.flights.collection_type
  standby_replicas  = var.opensearch.flights.standby_replicas
  firehose_role_arn = module.iam.firehose_role_arn
  dash_user_arns    = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/lake-admin"]
  vpc_id            = var.opensearch.flights.vpc_id
  tags              = var.tags
  
  depends_on = [module.iam]
}

module "kinesis_firehose_flights_enriched" {
  source                = "./modules/kinesis_firehose_flights_enriched"
  project_name          = var.project_name
  kinesis_firehose      = var.kinesis_firehose.flights_enriched
  kinesis_stream_arn    = module.kinesis_stream_flights_raw.kinesis_stream_flight_raw_arn
  bucket_arn            = data.aws_s3_bucket.landing.arn
  role_arn              = module.iam.firehose_role_arn
  # lambda_arn       = module.lambda_flights_enriched.lambda_arn
  opensearch_collection_endpoint = module.opensearch.collection_endpoint
  opensearch_index_name          = var.kinesis_firehose.flights_enriched.opensearch_index_name
  kms_firehose_arn  = module.kms.kms_firehose_arn
  # databases        = var.databases
  # tables           = var.tables
  environment       = var.environment
  tags              = var.tags
}

# main.tf ou modules.tf

module "cloudwatch_monitoring" {
  source = "./modules/cloudwatch_monitoring"
  
  project_name    = var.project_name
  aws_region      = var.aws_region
  environment     = var.environment
  tags            = var.tags
  
  # Kinesis
  kinesis_stream_name = var.kinesis_streams.flights_raw.name
  kinesis_stream_arn  = module.kinesis_stream_flights_raw.kinesis_stream_flight_raw_arn
  
  # Firehose
  firehose_s3_name        = var.kinesis_firehose.flights_enriched.name
  firehose_opensearch_name = "flight-radar-firehose-opensearch"
  
  # Lambda
  lambda_functions = [
    { 
      name = module.lambda_flights_raw.lambda_name, 
      arn = module.lambda_flights_raw.lambda_arn 
    },
    { 
      name = module.lambda_flights_enriched.lambda_name, 
      arn = module.lambda_flights_enriched.lambda_arn 
    }
  ]
  
  # ✅ OpenSearch Serverless (ATUALIZADO)
  opensearch_type            = "serverless"
  opensearch_collection_name = var.opensearch.flights.collection_name
  opensearch_collection_arn  = module.opensearch.collection_arn
  
  # Thresholds
  alarm_thresholds = var.alarm_thresholds
  
  # Notificações
  sns_alarm_topic_arn = module.cloudwatch_monitoring.sns_topic_arn
  alerts_email        = var.alerts_email
  
  depends_on = [
    module.kinesis_stream_flights_raw,
    module.kinesis_firehose_flights_enriched,
    module.opensearch,
    module.lambda_flights_raw,
    module.lambda_flights_enriched
  ]
}