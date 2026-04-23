resource "aws_kms_key" "firehose_kms" {
  description             = "KMS key para criptografia do Firehose flights"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = var.tags
}

resource "aws_kms_alias" "firehose_kms_alias" {
  name          = "alias/${var.project_name}-firehose-kms"
  target_key_id = aws_kms_key.firehose_kms.id
}
