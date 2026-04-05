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

resource "aws_iam_policy" "opensearch_dashboard_access" {
  name        = "${var.project_name}-opensearch-dashboard-access"
  description = "Acesso ao OpenSearch Dashboards para ${var.project_name}"
  policy      = data.aws_iam_policy_document.opensearch_dashboard_access.json
  
  tags = var.tags
}

# Anexar a policy aos usuários
resource "aws_iam_user_policy_attachment" "dashboard_access" {
  for_each = toset(var.dash_user_arns)
  
  user       = split("/", each.value)[1]  # Extrai nome do usuário do ARN
  policy_arn = aws_iam_policy.opensearch_dashboard_access.arn
}