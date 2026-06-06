# ============================================================================
# Outputs for Redshift Serverless Module
# ============================================================================

output "namespace_arn" {
  description = "ARN of Redshift Serverless namespace"
  value       = aws_redshiftserverless_namespace.flight_data.arn
}

output "namespace_id" {
  description = "ID of Redshift Serverless namespace"
  value       = aws_redshiftserverless_namespace.flight_data.id
}

output "namespace_name" {
  description = "Name of Redshift Serverless namespace"
  value       = aws_redshiftserverless_namespace.flight_data.namespace_name
}

output "workgroup_arn" {
  description = "ARN of Redshift Serverless workgroup"
  value       = aws_redshiftserverless_workgroup.flight_data.arn
}

output "workgroup_id" {
  description = "ID of Redshift Serverless workgroup"
  value       = aws_redshiftserverless_workgroup.flight_data.id
}

output "workgroup_name" {
  description = "Name of Redshift Serverless workgroup"
  value       = aws_redshiftserverless_workgroup.flight_data.workgroup_name
}

output "workgroup_endpoint" {
  description = "Endpoint of Redshift Serverless workgroup"
  value       = aws_redshiftserverless_workgroup.flight_data.endpoint[0].address
}

output "workgroup_port" {
  description = "Port for Redshift Serverless workgroup"
  value       = aws_redshiftserverless_workgroup.flight_data.endpoint[0].port
}

output "database_name" {
  description = "Database name"
  value       = var.database_name
}

output "admin_username" {
  description = "Admin username"
  value       = var.admin_username
  sensitive   = true
}

output "security_group_id" {
  description = "Security group ID for Redshift"
  value       = aws_security_group.redshift_sg.id
}

output "iam_role_arn" {
  description = "IAM role ARN for Redshift"
  value       = aws_iam_role.redshift_role.arn
}

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.redshift_logs.name
}

output "redshift_connection_string" {
  description = "JDBC connection string for Redshift"
  value       = "jdbc:redshift://${aws_redshiftserverless_workgroup.flight_data.endpoint[0].address}:${aws_redshiftserverless_workgroup.flight_data.endpoint[0].port}/${var.database_name}"
  sensitive   = true
}

output "redshift_psql_connection" {
  description = "psql connection command for CLI"
  value       = "psql -h ${aws_redshiftserverless_workgroup.flight_data.endpoint[0].address} -U ${var.admin_username} -d ${var.database_name}"
  sensitive   = true
}
