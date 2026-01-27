module "kinesis_data_stream" {
  source     = "./modules/kinesis_data_stream"
  project_name    = var.project_name
  kinesis_streams = var.kinesis_streams
  environment     = var.environment
  tags            = var.tags
}

# Compute Lambda role ARNs using naming pattern (breaks circular dependency)
# locals {
#   lambda_role_arns = [
#     for k, config in var.lambda_functions :
#     "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-lambda-${k}-role"
#     if config.enabled && config.requires_opensky_credentials
#   ]
# }

module "secrets_manager" {
  source = "./modules/secrets_manager"
  
  project_name         = var.project_name
  opensky_username     = var.opensky_username
  opensky_password     = var.opensky_password
  recovery_window_days = var.secrets_recovery_window_days
  log_retention_days   = var.secrets_log_retention_days
  tags = merge(var.tags, {
    Module = "secrets-manager"
  })
}

module "lambda_ingest" {
  for_each = {
    for k, v in var.lambda_functions :
    k => v if v.enabled && v.requires_opensky_credentials
  }

  source              = "./modules/lambda_ingest"
  project_name        = var.project_name
  region              = var.region
  lambda_config       = each.value
  lambda_key          = each.key
  kinesis_streams     = var.kinesis_streams
  opensky_secret_arn  = module.secrets_manager.secret_arn
  tags                = merge(var.tags, each.value.tags)
  
  depends_on = [module.kinesis_data_stream, module.secrets_manager]
}

 

module "eventbridge" {
  for_each = {
    for k, v in var.lambda_functions :
    k => v if v.enabled
  }

  source       = "./modules/eventbridge"
  lambda_key   = each.key
  lambda_config = each.value
  lambda_arn   = module.lambda_ingest[each.key].lambda_arn
  lambda_name  = module.lambda_ingest[each.key].lambda_name
  
  depends_on = [module.lambda_ingest]
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

