# ============================================================================
# IAM Policy Documents for Redshift
# ============================================================================

data "aws_iam_policy_document" "redshift_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["redshift.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# ============================================================================
# Custom Redshift Policies
# ============================================================================

data "aws_iam_policy_document" "redshift_custom_policy" {
  # S3 access for data loading
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
      "s3:GetObjectVersion"
    ]
    resources = [
      "arn:aws:s3:::*",
      "arn:aws:s3:::*/*"
    ]
  }

  # KMS for encrypted S3 data
  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey"
    ]
    resources = ["*"]
  }

  # SNS for notifications (alerts from KDA)
  statement {
    effect = "Allow"
    actions = [
      "sns:GetTopicAttributes",
      "sns:ListSubscriptionsByTopic"
    ]
    resources = [var.sns_topic_arn]
  }

  # CloudWatch Logs
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }

  # CloudWatch Metrics
  statement {
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricData"
    ]
    resources = ["*"]
  }
}
