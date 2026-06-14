output "db_instance_id" {
  description = "RDS instance identifier"
  value       = aws_db_instance.this.id
}

output "db_instance_arn" {
  description = "ARN of the RDS instance"
  value       = aws_db_instance.this.arn
}

output "db_name" {
  description = "Database name"
  value       = aws_db_instance.this.db_name
}

output "db_endpoint" {
  description = "RDS endpoint address"
  value       = aws_db_instance.this.address
}

output "db_port" {
  description = "RDS port"
  value       = aws_db_instance.this.port
}

output "db_hosted_zone_id" {
  description = "Route53 hosted zone ID for the endpoint"
  value       = aws_db_instance.this.hosted_zone_id
}

output "admin_username" {
  description = "Admin username"
  value       = var.admin_username
  sensitive   = true
}

output "security_group_id" {
  description = "RDS security group ID"
  value       = aws_security_group.rds.id
}

output "parameter_group_name" {
  description = "DB parameter group name"
  value       = aws_db_parameter_group.this.name
}

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.postgres.name
}

output "connection_string" {
  description = "PostgreSQL JDBC connection string"
  value       = "jdbc:postgresql://${aws_db_instance.this.address}:${aws_db_instance.this.port}/${aws_db_instance.this.db_name}"
  sensitive   = true
}

output "psql_connection" {
  description = "psql connection command"
  value       = "psql -h ${aws_db_instance.this.address} -U ${var.admin_username} -d ${aws_db_instance.this.db_name}"
  sensitive   = true
}

output "replicas" {
  description = "Read replica endpoints mapped by name"
  value = {
    for k, r in aws_db_instance.replica : k => {
      identifier = r.id
      endpoint   = r.address
      port       = r.port
      instance_class = r.instance_class
    }
  }
}
