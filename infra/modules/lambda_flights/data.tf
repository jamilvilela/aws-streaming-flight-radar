data "aws_caller_identity" "current" {}

data "archive_file" "lambda_function" {
  type        = "zip"
  source_dir  = "${path.root}/../app/lambda_flights/src"
  output_path = "${path.module}/.terraform/lambda_flights.zip"
}

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

