output "replication_instance_arn" {
  description = "ARN of the DMS replication instance"
  value       = aws_dms_replication_instance.this.replication_instance_arn
}

output "replication_instance_id" {
  description = "ID of the DMS replication instance"
  value       = aws_dms_replication_instance.this.replication_instance_id
}

output "replication_instance_private_ips" {
  description = "Private IPs of the DMS replication instance"
  value       = aws_dms_replication_instance.this.replication_instance_private_ips
}

output "source_endpoint_arn" {
  description = "ARN of the DMS source endpoint (RDS PostgreSQL)"
  value       = aws_dms_endpoint.source.endpoint_arn
}

output "target_endpoint_arn" {
  description = "ARN of the DMS target endpoint (S3 Parquet)"
  value       = aws_dms_s3_endpoint.target.endpoint_arn
}

output "task_arn" {
  description = "ARN of the DMS replication task"
  value       = aws_dms_replication_task.this.replication_task_arn
}

output "task_id" {
  description = "ID of the DMS replication task"
  value       = aws_dms_replication_task.this.replication_task_id
}

output "dms_security_group_id" {
  description = "DMS security group ID"
  value       = aws_security_group.dms.id
}

output "kms_key_arn" {
  description = "ARN of the DMS KMS key"
  value       = aws_kms_key.dms.arn
}

output "kms_key_alias" {
  description = "Alias of the DMS KMS key"
  value       = aws_kms_alias.dms.name
}

output "secrets_manager_secret_arn" {
  description = "ARN of the Secrets Manager secret for RDS credentials"
  value       = aws_secretsmanager_secret.rds_credentials.arn
}

output "secrets_manager_secret_name" {
  description = "Name of the Secrets Manager secret for RDS credentials"
  value       = aws_secretsmanager_secret.rds_credentials.name
}

output "iam_role_dms_s3_arn" {
  description = "ARN of the DMS S3 IAM role"
  value       = aws_iam_role.dms_s3.arn
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group for DMS"
  value       = aws_cloudwatch_log_group.dms.name
}

output "target_s3_path" {
  description = "S3 path where DMS writes Parquet data"
  value       = "s3://${var.landing_bucket_name}/dms/"
}
