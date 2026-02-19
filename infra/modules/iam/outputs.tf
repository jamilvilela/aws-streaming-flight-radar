output "lambda_execution_role_arn" {
  description = "ARN da role de execução da Lambda"
  value       = aws_iam_role.lambda_execution.arn
}

output "firehose_role_arn" {
  description = "ARN da role usada pelo Kinesis Firehose"
  value       = aws_iam_role.firehose_role.arn
}

output "firehose_policy_arn" {
  description = "ARN da policy inline do Firehose"
  value       = aws_iam_role_policy.firehose_policy.id
}
