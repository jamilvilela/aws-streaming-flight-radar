# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

# Archive the Lambda function code
data "archive_file" "lambda_function" {
  type        = "zip"
  source_file = "${path.module}/../../app/src/ingest_${var.lambda_key}/lambda_function.py"
  output_path = "${path.module}/.terraform/lambda_${var.lambda_key}.zip"
}