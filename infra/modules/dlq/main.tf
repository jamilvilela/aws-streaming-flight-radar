resource "aws_sqs_queue" "dlq" {
  name                       = "${var.project_name}-${var.name}"
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = 10
  kms_master_key_id          = var.kms_key_id
  sqs_managed_sse_enabled    = var.kms_key_id == null ? true : null

  redrive_policy = var.redrive_policy == null ? null : jsonencode(var.redrive_policy)

  tags = var.tags
}

resource "aws_sqs_queue_policy" "dlq" {
  count     = var.attach_queue_policy ? 1 : 0
  queue_url = aws_sqs_queue.dlq.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowProducerSend"
        Effect    = "Allow"
        Principal = { AWS = var.producer_role_arn }
        Action = [
          "sqs:SendMessage",
          "sqs:SendMessageBatch",
        ]
        Resource = aws_sqs_queue.dlq.arn
      },
    ]
  })
}
