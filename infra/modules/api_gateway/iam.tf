resource "aws_iam_role" "apigateway_authorizer" {
  count              = var.create_api_gateway ? 1 : 0
  name               = "${var.project_name}-${var.api_name}-authorizer-invoke-role"
  assume_role_policy = data.aws_iam_policy_document.apigateway_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "apigateway_authorizer_invoke" {
  count  = var.create_api_gateway ? 1 : 0
  name   = "${var.project_name}-${var.api_name}-authorizer-invoke-policy"
  role   = aws_iam_role.apigateway_authorizer[0].id
  policy = data.aws_iam_policy_document.apigateway_authorizer_invoke.json
}
