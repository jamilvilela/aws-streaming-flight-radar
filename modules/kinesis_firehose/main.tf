resource "aws_kinesis_firehose_delivery_stream" "this" {
  name        = var.name
  destination = "s3"

  kinesis_source_configuration {
    kinesis_stream_arn = var.kinesis_stream_arn
    role_arn           = var.firehose_role_arn
  }

  s3_configuration {
    role_arn           = var.firehose_role_arn
    bucket_arn         = var.raw_bucket_arn
    prefix             = var.prefix
    buffering_size     = 128
    buffering_interval = 300
    compression_format = "UNCOMPRESSED"
  }

  tags = var.tags
}