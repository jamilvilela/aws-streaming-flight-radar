output "function_arn" {
  value = aws_lambda_function.authorizer.arn
}

output "function_name" {
  value = aws_lambda_function.authorizer.function_name
}

output "function_invoke_arn" {
  value = aws_lambda_function.authorizer.invoke_arn
}

output "iam_role_arn" {
  value = aws_iam_role.authorizer.arn
}
