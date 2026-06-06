resource "aws_iam_role" "authorizer" {
  name               = "${var.project_name}-${var.lambda_config.name}-execution-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "logs" {
  name   = "${var.project_name}-${var.lambda_config.name}-logs-policy"
  role   = aws_iam_role.authorizer.id
  policy = data.aws_iam_policy_document.logs.json
}
