data "aws_caller_identity" "current" {}

data "archive_file" "python_layer" {
  type        = "zip"
  source_dir  = "${path.root}/../app/layers"
  output_path = "${path.module}/.terraform/python_layer.zip"
}

data "archive_file" "lambda_function" {
  type        = "zip"
  source_dir  = "${path.root}/../app/src/lambda_flights_raw"
  output_path = "${path.module}/.terraform/lambda_flights_raw.zip"
}

