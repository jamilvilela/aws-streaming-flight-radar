resource "aws_lambda_function" "authorizer" {
  function_name    = "${var.project_name}-${var.lambda_config.name}"
  role             = aws_iam_role.authorizer.arn
  handler          = var.lambda_config.handler
  runtime          = var.lambda_config.runtime
  filename         = data.archive_file.authorizer_function.output_path
  source_code_hash = data.archive_file.authorizer_function.output_base64sha256
  layers           = var.layer_arns
  timeout          = var.lambda_config.timeout
  memory_size      = var.lambda_config.memory_size

  ephemeral_storage { size = var.lambda_config.ephemeral_storage }

  environment {
    variables = var.environment_variables
  }

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "authorizer" {
  name              = "/aws/lambda/${aws_lambda_function.authorizer.function_name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}
