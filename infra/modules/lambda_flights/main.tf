resource "aws_lambda_function" "lambda_flights" {
  function_name    = "${var.project_name}-${var.lambda_config.name}"
  role             = aws_iam_role.lambda_execution.arn
  handler          = var.lambda_config.handler
  runtime          = var.lambda_config.runtime
  filename         = data.archive_file.lambda_function.output_path
  source_code_hash = data.archive_file.lambda_function.output_base64sha256
  timeout          = var.lambda_config.timeout
  memory_size      = var.lambda_config.memory_size

  ephemeral_storage {
    size = var.lambda_config.ephemeral_storage
  }

  reserved_concurrent_executions = var.reserved_concurrent_executions

  environment {
    variables = {
      KINESIS_STREAM = var.kinesis_stream_name
      DLQ_URL        = "" # populated by main.tf after the DLQ is created
      LOG_LEVEL      = "INFO"
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "log_group_lambda_flights" {
  name              = "/aws/lambda/${aws_lambda_function.lambda_flights.function_name}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}
