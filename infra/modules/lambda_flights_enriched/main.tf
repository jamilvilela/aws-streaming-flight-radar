resource "aws_lambda_function" "this" {
  function_name    = "${var.project_name}-${var.lambda_config.name}"
  role             = var.role_arn
  handler          = "lambda_function.lambda_handler"
  runtime          = var.lambda_config.runtime
  filename         = data.archive_file.lambda_function.output_path
  source_code_hash = data.archive_file.lambda_function.output_base64sha256
  timeout          = var.lambda_config.timeout
  memory_size      = var.lambda_config.memory_size
  ephemeral_storage {
    size = var.lambda_config.ephemeral_storage
  }
 
  environment {
    variables = {
      OUTPUT_STREAM = var.kinesis_firehose.name
      LOG_LEVEL      = "INFO"
    }
  }

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${aws_lambda_function.this.function_name}"
  retention_in_days = 7
}