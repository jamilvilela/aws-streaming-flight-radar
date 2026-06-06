data "aws_caller_identity" "current" {}

data "archive_file" "lambda_function" {
  type        = "zip"
  source_dir  = "${path.root}/../app/lambda_flights/src"
  output_path = "${path.module}/.terraform/lambda_flights.zip"
}
