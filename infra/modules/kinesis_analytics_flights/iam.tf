data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "kda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["kinesisanalytics.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "kda_policy" {
  statement {
    effect = "Allow"
    actions = [
      "kinesis:DescribeStream",
      "kinesis:DescribeStreamSummary",
      "kinesis:GetRecords",
      "kinesis:GetShardIterator",
      "kinesis:ListRecords",
      "kinesis:ListShards",
      "kinesis:ListStreams",
      "kinesis:PutRecord",
      "kinesis:PutRecords"
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:ListBucket",
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    resources = [
      "arn:aws:s3:::${var.s3_artifacts_bucket}",
      "arn:aws:s3:::${var.s3_artifacts_bucket}/*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricData"
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "kinesisanalytics:CreateApplicationSnapshot",
      "kinesisanalytics:DescribeApplicationSnapshot",
      "kinesisanalytics:DeleteApplicationSnapshot",
      "kinesisanalytics:ListApplicationSnapshots"
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey"
    ]
    resources = [
      "arn:aws:kms:${var.region}:${data.aws_caller_identity.current.account_id}:key/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values = [
        "kinesis.${var.region}.amazonaws.com",
        "s3.${var.region}.amazonaws.com"
      ]
    }
  }
}

resource "aws_iam_role" "kda_execution" {
  name               = "${var.project_name}-kda-execution-role"
  assume_role_policy = data.aws_iam_policy_document.kda_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "kda_policy" {
  name   = "${var.project_name}-kda-policy"
  role   = aws_iam_role.kda_execution.id
  policy = data.aws_iam_policy_document.kda_policy.json
}
