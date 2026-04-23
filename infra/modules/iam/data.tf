data "aws_iam_policy_document" "lambda_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda_kinesis_policy" {
  statement {
    actions = [
      "kinesis:PutRecord",
      "kinesis:PutRecords",
      "kinesis:ListShards",
      "kinesis:ListStreams",
      "kinesis:DescribeStream"
    ]
    resources = ["*"]
  }
}


data "aws_iam_policy_document" "lambda_logs_policy" {
  statement {
    actions   = [
      "logs:CreateLogGroup", 
      "logs:CreateLogStream", 
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

# Trust policy: permite que o serviço Firehose assuma a role
data "aws_iam_policy_document" "firehose_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "firehose_policy" {
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:PutObjectAcl"
    ]
    resources = [
      var.bucket_arn,
      "${var.bucket_arn}/*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "lambda:InvokeFunction"
    ]
    resources = ["*"] 
  }

  statement {
    effect = "Allow"
    actions = [
      "kinesis:DescribeStream",
      "kinesis:GetRecords",
      "kinesis:GetShardIterator",
      "kinesis:ListShards"
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "aoss:APIAccessAll",
      "aoss:CreateCollectionItems",
      "aoss:DeleteCollectionItems",
      "aoss:DescribeCollectionItems",
      "aoss:UpdateCollectionItems",
      "aoss:CreateIndex",
      "aoss:DeleteIndex",
      "aoss:WriteDocument",
      "aoss:ReadDocument",
      "aoss:UpdateIndex",
      "aoss:DescribeIndex"
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "opensearch_dashboard_access" {
  statement {
    effect = "Allow"
    actions = [
      "aoss:DashboardsRead",
      "aoss:DashboardsWrite",
      "aoss:DashboardsDelete",
      "aoss:DescribeCollectionItems",
      "aoss:ReadDocument",
      "aoss:WriteDocument"
    ]
    resources = ["*"]
  }
  
  statement {
    effect = "Allow"
    actions = [
      "aoss:ListCollections",
      "aoss:GetCollection"
    ]
    resources = ["*"]
  }
}

# ============================================================================
# KDA (Kinesis Data Analytics) ASSUME ROLE POLICY
# ============================================================================

data "aws_iam_policy_document" "kda_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["kinesisanalytics.amazonaws.com"]
    }
  }
}

# ============================================================================
# KDA POLICY: Acesso a Kinesis, S3, CloudWatch, etc
# ============================================================================

data "aws_iam_policy_document" "kda_policy" {
  # Kinesis streams: read source, write to sinks
  statement {
    effect = "Allow"
    actions = [
      "kinesis:DescribeStream",
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

  # S3: read JAR files, reference data, AND write checkpoints for state management
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
      "arn:aws:s3:::*",
      "arn:aws:s3:::*/*"
    ]
  }

  # CloudWatch: write logs
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

  # CloudWatch Metrics
  statement {
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricData"
    ]
    resources = ["*"]
  }

  # Snapshots (disaster recovery)
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

  # KMS: decrypt/encrypt checkpoints if using encrypted S3
  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey"
    ]
    resources = ["*"]
  }
}

# # Anexar a policy aos usuários
# resource "aws_iam_user_policy_attachment" "dashboard_access" {
#   for_each = toset(var.dash_user_arns)
  
#   user       = split("/", each.value)[1]  # Extrai nome do usuário do ARN
#   policy_arn = aws_iam_policy.opensearch_dashboard_access.arn
# }