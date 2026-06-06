# ============================================================================
# SNS Module - Outputs
# ============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for KDA alerts"
  value       = aws_sns_topic.kda_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic"
  value       = aws_sns_topic.kda_alerts.name
}

output "sns_topic_id" {
  description = "ID (ARN) of the SNS topic"
  value       = aws_sns_topic.kda_alerts.id
}

output "email_subscription_arns" {
  description = "ARNs of email subscriptions"
  value = {
    for email, sub in aws_sns_topic_subscription.kda_alerts_email :
    email => sub.arn
  }
}

output "sqs_subscription_arn" {
  description = "ARN of SQS subscription (if configured)"
  value       = try(aws_sns_topic_subscription.kda_alerts_sqs[0].arn, "")
}

output "lambda_subscription_arn" {
  description = "ARN of Lambda subscription (if configured)"
  value       = try(aws_sns_topic_subscription.kda_alerts_lambda[0].arn, "")
}

output "dlq_topic_arn" {
  description = "ARN of the SNS Dead Letter Queue topic"
  value       = aws_sns_topic.kda_alerts_dlq.arn
}

output "sns_console_url" {
  description = "AWS Console URL for SNS topic"
  value       = "https://console.aws.amazon.com/sns/v3/home#/topic/${aws_sns_topic.kda_alerts.arn}"
}

output "cloudwatch_alarm_arn" {
  description = "ARN of CloudWatch alarm for SNS publish failures (if created)"
  value       = try(aws_cloudwatch_metric_alarm.sns_publish_failures[0].arn, "")
}
