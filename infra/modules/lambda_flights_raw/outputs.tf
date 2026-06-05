output "lambda_arn" { value = aws_lambda_function.lambda_flights_raw.arn }
output "lambda_name" { value = aws_lambda_function.lambda_flights_raw.function_name }
output "log_group"   { value = aws_cloudwatch_log_group.log_group_flights_raw.name }
output "iam_role_arn" { value = aws_iam_role.lambda_execution.arn }