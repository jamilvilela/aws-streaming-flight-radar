# ============================================================================
# SNS Topic for KDA Alerts & Notifications
# ============================================================================
# Centralized notification hub for all Flink pipeline alerts
# Supports: Email, SMS, HTTP webhooks, SQS, Lambda
# ============================================================================

# ============================================================================
# SNS Topic for KDA Alerts
# ============================================================================

resource "aws_sns_topic" "kda_alerts" {
  name              = "${var.project_name}-kda-alerts"
  display_name      = "KDA Flink Alerts - ${var.project_name}"
  kms_master_key_id = var.kms_key_id != "" ? var.kms_key_id : null

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-kda-alerts"
      Environment = var.environment
      Purpose     = "KDA-Flink-Notifications"
    }
  )
}

# ============================================================================
# SNS Topic Policy - CloudWatch can publish
# ============================================================================

resource "aws_sns_topic_policy" "kda_alerts_cloudwatch" {
  arn = aws_sns_topic.kda_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.kda_alerts.arn
      }
    ]
  })
}

# ============================================================================
# Optional: SNS Topic Policy - Allow KDA service to publish
# ============================================================================

resource "aws_sns_topic_policy" "kda_alerts_kda_service" {
  count = var.allow_kda_publish ? 1 : 0
  arn   = aws_sns_topic.kda_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowKDAPublish"
        Effect = "Allow"
        Principal = {
          Service = "kinesisanalytics.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.kda_alerts.arn
      }
    ]
  })
}

# ============================================================================
# Email Subscriptions
# ============================================================================
# Note: Each subscription requires manual confirmation via email

resource "aws_sns_topic_subscription" "kda_alerts_email" {
  for_each = toset(var.alert_email_addresses)

  topic_arn = aws_sns_topic.kda_alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

# ============================================================================
# SQS Subscription (optional, for async processing)
# ============================================================================

resource "aws_sns_topic_subscription" "kda_alerts_sqs" {
  count = var.sqs_queue_arn != "" ? 1 : 0

  topic_arn = aws_sns_topic.kda_alerts.arn
  protocol  = "sqs"
  endpoint  = var.sqs_queue_arn

  # Enable raw message delivery for SQS
  raw_message_delivery = true
}

# ============================================================================
# Lambda Subscription (optional, for custom processing)
# ============================================================================

resource "aws_sns_topic_subscription" "kda_alerts_lambda" {
  count = var.lambda_function_arn != "" ? 1 : 0

  topic_arn = aws_sns_topic.kda_alerts.arn
  protocol  = "lambda"
  endpoint  = var.lambda_function_arn
}

# ============================================================================
# SNS Topic Attribute: Delivery Status Logging (for monitoring)
# ============================================================================

resource "aws_sns_topic" "kda_alerts_dlq" {
  name = "${var.project_name}-kda-alerts-dlq"

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-kda-alerts-dlq"
      Environment = var.environment
      Purpose     = "KDA-Flink-DLQ"
    }
  )
}

# ============================================================================
# CloudWatch Log Group for SNS Delivery Status Logging
# ============================================================================

resource "aws_cloudwatch_log_group" "sns_delivery_logs" {
  count = var.enable_delivery_status_logging ? 1 : 0

  name              = "/aws/sns/${var.project_name}/kda-alerts"
  retention_in_days = 7

  tags = var.tags
}

# ============================================================================
# IAM Role for SNS Delivery Status Logging to CloudWatch
# ============================================================================

resource "aws_iam_role" "sns_delivery_status" {
  count = var.enable_delivery_status_logging ? 1 : 0

  name = "${var.project_name}-sns-delivery-status"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "sns_delivery_status" {
  count = var.enable_delivery_status_logging ? 1 : 0

  name = "${var.project_name}-sns-delivery-status-policy"
  role = aws_iam_role.sns_delivery_status[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.sns_delivery_logs[0].arn}:*"
      }
    ]
  })
}

# ============================================================================
# CloudWatch Alarm for SNS Publish Failures
# ============================================================================

resource "aws_cloudwatch_metric_alarm" "sns_publish_failures" {
  count = var.create_publish_failure_alarm ? 1 : 0

  alarm_name          = "${var.project_name}-sns-publish-failures"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "NumberOfNotificationsFailed"
  namespace           = "AWS/SNS"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Alert when SNS fails to publish messages"
  treat_missing_data  = "notBreaching"

  dimensions = {
    TopicName = aws_sns_topic.kda_alerts.name
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-sns-publish-failures"
    }
  )
}
