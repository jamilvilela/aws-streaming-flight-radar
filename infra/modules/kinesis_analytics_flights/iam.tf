resource "aws_iam_role" "kda_execution" {
  name               = "${var.project_name}-kda-execution-role"
  assume_role_policy = data.aws_iam_policy_document.kda_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "kda_policy" {
  name   = "${var.project_name}-kda-policy"
  role   = aws_iam_role.kda_execution.id
  policy = data.aws_iam_policy_document.kda_policy.json
}
