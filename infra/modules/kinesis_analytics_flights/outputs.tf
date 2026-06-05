output "kda_application_arn" {
  description = "ARN da aplicação Kinesis Data Analytics"
  value       = aws_kinesisanalyticsv2_application.kda_flights.arn
}

output "kda_application_name" {
  description = "Nome da aplicação Kinesis Data Analytics"
  value       = aws_kinesisanalyticsv2_application.kda_flights.name
}

output "kda_application_id" {
  description = "ID da aplicação Kinesis Data Analytics"
  value       = aws_kinesisanalyticsv2_application.kda_flights.id
}

output "kda_log_group_name" {
  description = "Nome do CloudWatch Log Group para KDA"
  value       = aws_cloudwatch_log_group.kda_flights_log_group.name
}

output "kda_log_group_arn" {
  description = "ARN do CloudWatch Log Group para KDA"
  value       = aws_cloudwatch_log_group.kda_flights_log_group.arn
}

output "iam_role_arn" {
  description = "ARN da role IAM de execução do KDA (Kinesis Data Analytics)"
  value       = aws_iam_role.kda_execution.arn
}

# output "kda_snapshot_arn" {
#   description = "ARN do snapshot da aplicação Flink"
#   value       = aws_kinesisanalyticsv2_application_snapshot.kda_flights_snapshot.arn
# }

# output "sns_topic_arn" {
#   description = "ARN of SNS topic for KDA alerts"
#   value       = aws_sns_topic.kda_alerts.arn
# }

# output "dashboard_url" {
#   description = "URL to CloudWatch dashboard"
#   value       = "https://console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.kda_flights.dashboard_name}"
# }

