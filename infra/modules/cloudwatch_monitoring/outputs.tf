output "dashboard_name" {
  description = "Nome do dashboard CloudWatch"
  value       = aws_cloudwatch_dashboard.streaming_pipeline.dashboard_name
}

output "dashboard_arn" {
  description = "ARN do dashboard CloudWatch"
  value       = aws_cloudwatch_dashboard.streaming_pipeline.dashboard_arn
}

output "dashboard_url" {
  description = "URL do dashboard CloudWatch"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.streaming_pipeline.dashboard_name}"
}