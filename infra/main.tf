module "kinesis_stream_flights_raw" {
  source     = "./modules/kinesis_stream_flights_raw"
  project_name    = var.project_name
  kinesis_stream = var.kinesis_streams["flights_raw"]
  environment     = var.environment
  tags            = var.tags
}

module "kinesis_firehose_flights_enriched" {
  source           = "./modules/kinesis_firehose_flights_enriched"
  project_name     = var.project_name
  kinesis_firehose = var.kinesis_firehose["flights_enriched"]
  kinesis_stream_arn = module.kinesis_stream_flights_raw.kinesis_stream_flight_raw_arn
  bucket_arn       = data.aws_s3_bucket.landing.arn
  role_arn         = module.iam.firehose_role_arn
  lambda_arn       = module.lambda_flights_enriched.lambda_arn
  environment      = var.environment
  tags             = var.tags
}


module "iam" {
  source       = "./modules/iam"
  project_name = var.project_name
  tags         = var.tags
  kinesis_arns = [
    module.kinesis_stream_flights_raw.kinesis_stream_flight_raw_arn
  ]
  bucket_arn = data.aws_s3_bucket.landing.arn
  lambda_arn = module.lambda_flights_enriched.lambda_arn
}

module "lambda_flights_raw" {
  source              = "./modules/lambda_flights_raw"
  project_name        = var.project_name
  aws_region          = var.aws_region
  lambda_config       = var.lambda_functions["flights_raw"]
  kinesis_stream      = var.kinesis_streams["flights_raw"]
  tags                = var.tags
  role_arn            = module.iam.lambda_execution_role_arn
  depends_on = [ 
    module.iam, 
    module.kinesis_firehose_flights_enriched 
  ]
}

module "lambda_flights_enriched" {
  source              = "./modules/lambda_flights_enriched"
  project_name        = var.project_name
  aws_region          = var.aws_region 
  lambda_config       = var.lambda_functions["flights_enriched"]
  kinesis_firehose    = var.kinesis_firehose["flights_enriched"]
  role_arn            = module.iam.lambda_execution_role_arn
  tags                = var.tags
  depends_on = [ 
    module.iam
  ]
}