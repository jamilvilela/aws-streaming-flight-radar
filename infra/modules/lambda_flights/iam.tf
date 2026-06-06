data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda_kinesis" {
  statement {
    actions = [
      "kinesis:PutRecord",
      "kinesis:PutRecords",
      "kinesis:DescribeStream",
    ]
    resources = [var.kinesis_stream_arn]
  }
}

data "aws_iam_policy_document" "lambda_sqs_dlq" {
  statement {
    actions = [
      "sqs:SendMessage",
      "sqs:SendMessageBatch",
    ]
    resources = [var.dlq_queue_arn]
  }
}

data "aws_iam_policy_document" "lambda_logs" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project_name}-${var.lambda_config.name}",
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project_name}-${var.lambda_config.name}:*",
    ]
  }
}

resource "aws_iam_role" "lambda_execution" {
  name               = "${var.project_name}-${var.lambda_config.name}-execution-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "lambda_kinesis_policy" {
  name   = "${var.project_name}-${var.lambda_config.name}-kinesis-policy"
  role   = aws_iam_role.lambda_execution.id
  policy = data.aws_iam_policy_document.lambda_kinesis.json
}

resource "aws_iam_role_policy" "lambda_sqs_dlq_policy" {
  name   = "${var.project_name}-${var.lambda_config.name}-dlq-policy"
  role   = aws_iam_role.lambda_execution.id
  policy = data.aws_iam_policy_document.lambda_sqs_dlq.json
}

resource "aws_iam_role_policy" "lambda_logs_policy" {
  name   = "${var.project_name}-${var.lambda_config.name}-logs-policy"
  role   = aws_iam_role.lambda_execution.id
  policy = data.aws_iam_policy_document.lambda_logs.json
}
