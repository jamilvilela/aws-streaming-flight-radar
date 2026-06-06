data "archive_file" "authorizer_function" {
  type        = "zip"
  source_dir  = "${path.root}/../app/lambda_authorizer/src"
  output_path = "${path.module}/.terraform/lambda_authorizer.zip"
}
