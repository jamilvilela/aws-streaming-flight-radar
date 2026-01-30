# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

# Archive the Lambda function code
data "archive_file" "lambda_function" {
  type        = "zip"
  source_file = "${path.root}/../app/src/ingest_${var.lambda_key}/lambda_function.py"
  output_path = "${path.module}/.terraform/lambda_${var.lambda_key}.zip"
}

data "archive_file" "python_layer" {
  type        = "zip"
  source_file = "${path.root}/../app/layers/python_layer.zip"
  output_path = "${path.module}/.terraform/lambda_python_layer.zip"
}
