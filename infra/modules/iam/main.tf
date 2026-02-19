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
    resources = var.kinesis_arns
  }
}


data "aws_iam_policy_document" "lambda_logs_policy" {
  statement {
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_role" "lambda_execution" {
  name = "${var.project_name}-lambda-execution-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
  tags = var.tags
}


resource "aws_iam_role_policy" "lambda_kinesis_policy" {
  name = "${var.project_name}-lambda-kinesis-policy"
  role = aws_iam_role.lambda_execution.id
  policy = data.aws_iam_policy_document.lambda_kinesis_policy.json
}
resource "aws_iam_role_policy" "lambda_logs_policy" {
  name = "${var.project_name}-lambda-logs-policy"
  role = aws_iam_role.lambda_execution.id
  policy = data.aws_iam_policy_document.lambda_logs_policy.json
}


# Role para o Kinesis Firehose
resource "aws_iam_role" "firehose_role" {
  name               = "${var.project_name}-firehose-role"
  assume_role_policy = data.aws_iam_policy_document.firehose_assume_role_policy.json
  tags               = var.tags
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

# Policy para Firehose acessar S3 e invocar Lambda
resource "aws_iam_role_policy" "firehose_policy" {
  name   = "${var.project_name}-firehose-policy"
  role   = aws_iam_role.firehose_role.id
  policy = data.aws_iam_policy_document.firehose_policy.json
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
    resources = [var.lambda_arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "kinesis:DescribeStream",
      "kinesis:GetRecords",
      "kinesis:GetShardIterator",
      "kinesis:ListShards"
    ]
    resources = var.kinesis_arns
  }
}
