output "function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.lambda_flights.arn
}

output "function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.lambda_flights.function_name
}

output "function_invoke_arn" {
  description = "Invoke ARN (used by API Gateway)"
  value       = aws_lambda_function.lambda_flights.invoke_arn
}

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.log_group_lambda_flights.name
}

output "iam_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.arn
}
