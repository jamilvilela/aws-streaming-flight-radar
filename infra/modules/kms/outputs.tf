output "kms_firehose_arn" {
  value = aws_kms_key.firehose_kms.arn
}
