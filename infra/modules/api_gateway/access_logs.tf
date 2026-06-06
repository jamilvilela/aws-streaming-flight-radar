resource "aws_cloudwatch_log_group" "apigw_access" {
  count             = var.enable_access_logs ? 1 : 0
  name              = "/aws/apigateway/${var.project_name}-${var.api_name}/access"
  retention_in_days = var.access_log_retention_days
  tags              = var.tags
}
