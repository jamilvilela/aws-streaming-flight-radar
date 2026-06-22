output "kinesis_stream_flights_info" {
  value = module.kinesis_stream_flights.kinesis_streams_info
}

output "lambda_flights_function_arn" {
  value = module.lambda_flights.function_arn
}

output "lambda_flights_function_name" {
  value = module.lambda_flights.function_name
}

output "lambda_flights_iam_role_arn" {
  value = module.lambda_flights.iam_role_arn
}

output "flights_dlq_url" {
  value = module.flights_dlq.queue_url
}

output "flights_dlq_arn" {
  value = module.flights_dlq.queue_arn
}

output "api_invoke_url" {
  description = "Base invoke URL of the edge API (e.g. https://<id>.execute-api.us-east-1.amazonaws.com/v1)"
  value       = module.api_gateway.stage_invoke_url
}

output "api_id" {
  value = module.api_gateway.api_id
}

output "api_key_id" {
  value = module.api_gateway.api_key_id
}

output "api_key_value" {
  value     = module.api_gateway.api_key_value
  sensitive = true
}

# ============================================================================
# Aurora Serverless v2 outputs
# ============================================================================

output "aurora_endpoint" {
  description = "Aurora Serverless v2 cluster writer endpoint address"
  value       = module.aurora_postgres.db_endpoint
}

output "aurora_reader_endpoint" {
  description = "Aurora Serverless v2 cluster reader endpoint address"
  value       = module.aurora_postgres.db_reader_endpoint
}

output "aurora_port" {
  description = "Aurora Serverless v2 cluster port"
  value       = module.aurora_postgres.db_port
}

output "aurora_db_name" {
  description = "Aurora Serverless v2 database name"
  value       = module.aurora_postgres.db_name
}

output "aurora_cluster_arn" {
  description = "ARN of the Aurora cluster"
  value       = module.aurora_postgres.cluster_arn
}

output "aurora_security_group_id" {
  description = "Aurora Serverless v2 security group ID"
  value       = module.aurora_postgres.security_group_id
}

output "aurora_connection" {
  description = "Aurora connection string for psql"
  value       = module.aurora_postgres.aurora_connection
  sensitive   = true
}

output "aurora_admin_username" {
  description = "Aurora Serverless v2 admin username"
  value       = module.aurora_postgres.admin_username
  sensitive   = true
}

# ============================================================================
# DMS Serverless outputs
# ============================================================================

output "dms_replication_config_arn" {
  description = "ARN of the DMS Serverless replication config"
  value       = try(module.dms_serverless[0].replication_config_arn, null)
}

output "dms_replication_config_id" {
  description = "ID of the DMS Serverless replication config"
  value       = try(module.dms_serverless[0].replication_config_id, null)
}

output "dms_replication_config_identifier" {
  description = "Identifier (name) of the DMS Serverless replication config"
  value       = try(module.dms_serverless[0].replication_config_identifier, null)
}

output "dms_source_endpoint_arn" {
  description = "ARN of the DMS source endpoint (Aurora PostgreSQL)"
  value       = try(module.dms_serverless[0].source_endpoint_arn, null)
}

output "dms_target_endpoint_arn" {
  description = "ARN of the DMS target endpoint (S3 Parquet)"
  value       = try(module.dms_serverless[0].target_endpoint_arn, null)
}

output "dms_security_group_id" {
  description = "DMS Serverless security group ID"
  value       = try(module.dms_serverless[0].dms_security_group_id, null)
}
