resource "aws_scheduler_schedule" "lambda_schedule" {
  name                = "${var.lambda_key}-ingest-schedule"
  schedule_expression = var.lambda_config.schedule
  state               = var.lambda_config.enabled ? "ENABLED" : "DISABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = var.lambda_arn
    role_arn = aws_iam_role.scheduler_role.arn

    retry_policy {
      maximum_event_age_in_seconds = 3600
      maximum_retry_attempts       = 2
    }

    # dead_letter_config {
    #   arn = null
    # }
  }
}

# IAM Role for EventBridge Scheduler
resource "aws_iam_role" "scheduler_role" {
  name = "${var.lambda_key}-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.lambda_key}-scheduler-role"
  }
}

# IAM Policy for Scheduler to invoke Lambda
resource "aws_iam_role_policy" "scheduler_lambda_policy" {
  name = "${var.lambda_key}-scheduler-lambda-policy"
  role = aws_iam_role.scheduler_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = var.lambda_arn
      }
    ]
  })
}

# Lambda permission for Scheduler to invoke
resource "aws_lambda_permission" "allow_scheduler" {
  statement_id  = "AllowExecutionFromScheduler"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_name
  principal     = "scheduler.amazonaws.com"
  source_arn    = aws_scheduler_schedule.lambda_schedule.arn
}