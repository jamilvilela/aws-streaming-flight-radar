resource "aws_iam_role" "lambda_execution" {
  name               = "${var.project_name}-${var.lambda_config.name}-execution-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "lambda_kinesis_policy" {
  name   = "${var.project_name}-${var.lambda_config.name}-kinesis-policy"
  role   = aws_iam_role.lambda_execution.id
  policy = data.aws_iam_policy_document.lambda_kinesis.json
}

resource "aws_iam_role_policy" "lambda_sqs_dlq_policy" {
  name   = "${var.project_name}-${var.lambda_config.name}-dlq-policy"
  role   = aws_iam_role.lambda_execution.id
  policy = data.aws_iam_policy_document.lambda_sqs_dlq.json
}

resource "aws_iam_role_policy" "lambda_logs_policy" {
  name   = "${var.project_name}-${var.lambda_config.name}-logs-policy"
  role   = aws_iam_role.lambda_execution.id
  policy = data.aws_iam_policy_document.lambda_logs.json
}
