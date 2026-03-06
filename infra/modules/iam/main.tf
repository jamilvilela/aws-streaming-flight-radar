resource "aws_iam_role" "lambda_execution" {
  name = "${var.project_name}-lambda-execution-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
  tags = var.tags
}


resource "aws_iam_role_policy" "lambda_kinesis_policy" {
  name = "${var.project_name}-lambda-kinesis-policy"
  role = aws_iam_role.lambda_execution.id
  policy = data.aws_iam_policy_document.lambda_kinesis_policy.json
}
resource "aws_iam_role_policy" "lambda_logs_policy" {
  name = "${var.project_name}-lambda-logs-policy"
  role = aws_iam_role.lambda_execution.id
  policy = data.aws_iam_policy_document.lambda_logs_policy.json
}

# Kinesis Firehose
resource "aws_iam_role" "firehose_role" {
  name               = "${var.project_name}-firehose-role"
  assume_role_policy = data.aws_iam_policy_document.firehose_assume_role_policy.json
  tags               = var.tags
}

# Policy para Firehose acessar S3 e invocar Lambda
resource "aws_iam_role_policy" "firehose_policy" {
  name   = "${var.project_name}-firehose-policy"
  role   = aws_iam_role.firehose_role.id
  policy = data.aws_iam_policy_document.firehose_policy.json
}
