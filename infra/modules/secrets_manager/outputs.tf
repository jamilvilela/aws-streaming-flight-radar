output "secret_arn" {
  description = "ARN of the OpenSky credentials secret"
  value       = aws_secretsmanager_secret.opensky_credentials.arn
}

output "secret_id" {
  description = "ID/Name of the OpenSky credentials secret"
  value       = aws_secretsmanager_secret.opensky_credentials.id
}

output "secret_version_id" {
  description = "Version ID of the secret"
  value       = aws_secretsmanager_secret_version.opensky_credentials.version_id
}

output "secret_access_policy" {
  description = "ARN of the secret with access policy applied"
  value       = length(aws_secretsmanager_secret_policy.opensky_credentials) > 0 ? aws_secretsmanager_secret_policy.opensky_credentials[0].secret_arn : null
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group for secret access audit logs"
  value       = aws_cloudwatch_log_group.secrets_access_logs.name
}
