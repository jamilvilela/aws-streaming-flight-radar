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
# RDS PostgreSQL outputs
# ============================================================================

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint address"
  value       = module.rds_postgres.db_endpoint
}

output "rds_port" {
  description = "RDS PostgreSQL port"
  value       = module.rds_postgres.db_port
}

output "rds_db_name" {
  description = "RDS PostgreSQL database name"
  value       = module.rds_postgres.db_name
}

output "rds_instance_arn" {
  description = "ARN of the RDS instance"
  value       = module.rds_postgres.db_instance_arn
}

output "rds_security_group_id" {
  description = "RDS security group ID"
  value       = module.rds_postgres.security_group_id
}

output "rds_psql_connection" {
  description = "psql connection command"
  value       = module.rds_postgres.psql_connection
  sensitive   = true
}

output "rds_admin_username" {
  description = "RDS PostgreSQL admin username"
  value       = module.rds_postgres.admin_username
  sensitive   = true
}

output "rds_connection_string" {
  description = "JDBC connection string"
  value       = module.rds_postgres.connection_string
  sensitive   = true
}

# ============================================================================
# DMS outputs
# ============================================================================

output "dms_replication_instance_arn" {
  description = "ARN of the DMS replication instance"
  value       = try(module.dms[0].replication_instance_arn, null)
}

output "dms_replication_instance_id" {
  description = "ID of the DMS replication instance"
  value       = try(module.dms[0].replication_instance_id, null)
}

output "dms_source_endpoint_arn" {
  description = "ARN of the DMS source endpoint (RDS PostgreSQL)"
  value       = try(module.dms[0].source_endpoint_arn, null)
}

output "dms_target_endpoint_arn" {
  description = "ARN of the DMS target endpoint (S3 Parquet)"
  value       = try(module.dms[0].target_endpoint_arn, null)
}

output "dms_task_arn" {
  description = "ARN of the DMS replication task"
  value       = try(module.dms[0].task_arn, null)
}

output "dms_task_id" {
  description = "ID of the DMS replication task"
  value       = try(module.dms[0].task_id, null)
}

output "dms_kms_key_arn" {
  description = "ARN of the DMS KMS key"
  value       = try(module.dms[0].kms_key_arn, null)
}

output "dms_secrets_manager_secret_arn" {
  description = "ARN of the Secrets Manager secret (RDS credentials)"
  value       = try(module.dms[0].secrets_manager_secret_arn, null)
}

output "dms_target_s3_path" {
  description = "S3 path where DMS writes Parquet data"
  value       = try(module.dms[0].target_s3_path, null)
}

output "rds_replicas" {
  description = "Read replica endpoints"
  value       = module.rds_postgres.replicas
}
