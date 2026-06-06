resource "aws_lambda_function" "lambda_flights" {
  function_name    = "${var.project_name}-${var.lambda_config.name}"
  role             = aws_iam_role.lambda_execution.arn
  handler          = var.lambda_config.handler
  runtime          = var.lambda_config.runtime
  filename         = data.archive_file.lambda_function.output_path
  source_code_hash = data.archive_file.lambda_function.output_base64sha256
  layers           = var.layer_arns
  timeout          = var.lambda_config.timeout
  memory_size      = var.lambda_config.memory_size

  ephemeral_storage {
    size = var.lambda_config.ephemeral_storage
  }

  reserved_concurrent_executions = var.reserved_concurrent_executions

  environment {
    variables = {
      KINESIS_STREAM = var.kinesis_stream_name
      DLQ_URL        = var.dlq_queue_url
      DLQ_ARN        = var.dlq_queue_arn
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

resource "aws_lambda_function_event_invoke_config" "lambda_flights" {
  function_name = aws_lambda_function.lambda_flights.function_name

  destination_config {
    on_failure {
      destination = var.dlq_queue_arn
    }
  }
}

resource "aws_lambda_permission" "apigateway_invoke" {
  count         = var.api_gateway_execution_arn != "" ? 1 : 0
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_flights.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = var.api_gateway_execution_arn
}
