###############################################################################
# Account-level API Gateway settings
#
# Required to enable access logs on a stage. API Gateway needs to assume an IAM
# role to write to CloudWatch Logs; that role ARN must be set on the
# account-level settings (singleton per AWS account/region) before any stage
# can ship logs.
###############################################################################

resource "aws_iam_role" "apigw_cloudwatch_logs" {
  count              = var.enable_access_logs ? 1 : 0
  name               = "${var.project_name}-${var.api_name}-apigw-logs-role"
  assume_role_policy = data.aws_iam_policy_document.apigw_logs_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "apigw_cloudwatch_logs" {
  count  = var.enable_access_logs ? 1 : 0
  name   = "${var.project_name}-${var.api_name}-apigw-logs-policy"
  role   = aws_iam_role.apigw_cloudwatch_logs[0].id
  policy = data.aws_iam_policy_document.apigw_logs_policy.json
}

# Singleton resource per AWS account/region — this is what unblocks
# aws_api_gateway_stage when access_log_settings is set.
resource "aws_api_gateway_account" "this" {
  count               = var.enable_access_logs ? 1 : 0
  cloudwatch_role_arn = aws_iam_role.apigw_cloudwatch_logs[0].arn
}
