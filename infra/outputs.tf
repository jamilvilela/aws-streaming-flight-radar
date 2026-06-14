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

output "rds_connection_string" {
  description = "JDBC connection string"
  value       = module.rds_postgres.connection_string
  sensitive   = true
}

output "rds_replicas" {
  description = "Read replica endpoints"
  value       = module.rds_postgres.replicas
}
