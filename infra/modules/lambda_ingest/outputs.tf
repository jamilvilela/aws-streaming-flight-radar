output "lambda_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.lambda_function.arn
}

output "lambda_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.lambda_function.function_name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

output "lambda_log_group" {
  description = "Name of the CloudWatch Log Group for Lambda"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "lambda_config_summary" {
  description = "Resumo das configurações da Lambda"
  value = {
    function_name     = aws_lambda_function.lambda_function.function_name
    function_arn      = aws_lambda_function.lambda_function.arn
    runtime           = aws_lambda_function.lambda_function.runtime
    timeout           = aws_lambda_function.lambda_function.timeout
    memory_size       = aws_lambda_function.lambda_function.memory_size
    handler           = aws_lambda_function.lambda_function.handler
    role_arn          = aws_iam_role.lambda_role.arn
    log_group         = aws_cloudwatch_log_group.lambda_logs.name
    ephemeral_storage = aws_lambda_function.lambda_function.ephemeral_storage[0].size
    concurrency_mode  = var.lambda_config.reserved_concurrent_executions > 0 ? "PROVISIONED" : "ON_DEMAND"
    concurrency_value = var.lambda_config.reserved_concurrent_executions
  }
}
