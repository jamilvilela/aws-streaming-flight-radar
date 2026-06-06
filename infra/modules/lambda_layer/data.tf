data "archive_file" "layer" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = var.output_path
}
