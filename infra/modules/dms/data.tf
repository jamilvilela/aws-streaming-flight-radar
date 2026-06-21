data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_vpc" "this" {
  id = var.vpc_id
}

data "aws_iam_policy_document" "dms_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      # DMS now requires the regional service principal (dms.<region>.amazonaws.com)
      # for the trust relationship. Keep both for backward compatibility.
      identifiers = ["dms.${var.region}.amazonaws.com", "dms.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "dms_vpc_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["dms.${var.region}.amazonaws.com", "dms.amazonaws.com"]
    }
  }
}

# Additional EC2 permissions for DMS VPC role — DMS may require these
# when creating/destroying elastic network interfaces in the VPC.
data "aws_iam_policy_document" "dms_vpc_ec2" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:ModifyNetworkInterfaceAttribute",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcs",
      "ec2:DescribeSecurityGroups",
      "ec2:CreateNetworkInterfacePermission"
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "dms_cloudwatch_logs" {
  statement {
    effect = "Allow"
    actions = [
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:PutMetricFilter",
      "logs:DescribeMetricFilters"
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "dms_s3_access" {
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:DeleteObject",
      "s3:PutObjectTagging"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:s3:::${var.landing_bucket_name}",
      "arn:${data.aws_partition.current.partition}:s3:::${var.landing_bucket_name}/*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:s3:::${var.landing_bucket_name}"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:ReEncrypt*"
    ]
    resources = [aws_kms_key.dms.arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue"
    ]
    resources = [data.aws_secretsmanager_secret.rds_credentials.arn]
  }
}

# Route tables in the VPC (used by Gateway Endpoints for S3)
data "aws_route_tables" "dms" {
  vpc_id = var.vpc_id
}
