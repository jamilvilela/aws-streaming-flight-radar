resource "aws_lambda_layer_version" "this" {
  layer_name          = "${var.project_name}-${var.layer_name}"
  filename            = data.archive_file.layer.output_path
  source_code_hash    = data.archive_file.layer.output_base64sha256
  compatible_runtimes = var.compatible_runtimes
  description         = var.description
}
