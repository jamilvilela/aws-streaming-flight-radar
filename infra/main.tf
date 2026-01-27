module "kinesis_data_stream" {
  source     = "./modules/kinesis_data_stream"
  project_name  = var.project_name
  kinesis_streams    = var.kinesis_streams
}

module "lambda_ingest" {
  source        = "./modules/lambda_ingest"
  project_name  = var.project_name
  kinesis_arns  = module.kinesis_data_stream.kinesis_stream_arns
  timeout       = var.lambda_ingest_timeout
  depends_on = [ module.kinesis_data_stream ]
}

module "eventbridge" {
  source         = "./modules/eventbridge"
  lambda_arns    = module.lambda_ingest.ingest_lambda_arns
  schedule       = var.ingestion_schedule
  depends_on = [ module.lambda_ingest ]
}

# module "lambda_processor" {
#   source        = "./modules/lambda_processor"
#   project_name  = var.project_name
#   kinesis_arns  = module.kinesis_data_stream.stream_arns
#   dynamodb_arns = module.dynamodb.table_arns
#   timeout       = var.lambda_processor_timeout
#   depends_on = [ module.dynamodb, module.kinesis_data_stream ]
# }


# module "dynamodb" {
#   source = "./modules/dynamodb"
#   tables = ["flights", "airports", "airplanes"]
# }

