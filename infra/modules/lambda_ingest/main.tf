resource "aws_lambda_function" "lambda_function" {
  filename         = data.archive_file.lambda_function.output_path
  source_code_hash = data.archive_file.lambda_function.output_base64sha256
  function_name    = "${var.project_name}-${var.lambda_config.name}"
  role             = aws_iam_role.lambda_role.arn
  handler          = var.lambda_config.handler
  runtime          = var.lambda_config.runtime
  timeout          = var.lambda_config.timeout
  memory_size      = var.lambda_config.memory_size
  
  ephemeral_storage {
    size = var.lambda_config.ephemeral_storage
  }

  # ON-DEMAND: 0 = sem provisionamento de concorrência (pay-per-use)
  # Valor > 0 = provisionado (custo fixo)
  reserved_concurrent_executions = var.lambda_config.reserved_concurrent_executions > 0 ? var.lambda_config.reserved_concurrent_executions : -1

  layers = var.lambda_layers

  environment {
    variables = merge({
      KINESIS_STREAM = var.kinesis_streams[var.lambda_key].stream_name
      LOG_LEVEL      = "INFO"
      }, 
      var.lambda_config.requires_opensky_credentials ? {
        OPENSKY_SECRET_ARN = var.opensky_secret_arn
      } : {}
    )
  }

  dynamic "vpc_config" {
    for_each = var.enable_vpc && length(var.subnet_ids) > 0 ? [1] : []
    content {
      subnet_ids         = var.subnet_ids
      security_group_ids = var.security_group_ids
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.lambda_config.name}"
    }
  )

  depends_on = [
    aws_iam_role_policy.lambda_kinesis_policy,
    aws_iam_role_policy.lambda_logs_policy
  ]
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.lambda_function.function_name}"
  retention_in_days = var.log_retention_days

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.lambda_config.name}-logs"
    }
  )
}

# Lambda Insights (optional, para melhor observabilidade)
resource "aws_cloudwatch_log_group" "lambda_insights" {
  count             = var.enable_lambda_insights ? 1 : 0
  name              = "/aws/lambda-insights:${aws_lambda_function.lambda_function.function_name}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-${var.lambda_key}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

# Policy for Kinesis write access
resource "aws_iam_role_policy" "lambda_kinesis_policy" {
  name   = "${var.project_name}-lambda-${var.lambda_key}-kinesis-policy"
  role   = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "kinesis:PutRecord",
        "kinesis:PutRecords",
        "kinesis:ListShards",
        "kinesis:ListStreams",
        "kinesis:DescribeStream"
      ]
      Resource = "arn:aws:kinesis:${var.region}:${data.aws_caller_identity.current.account_id}:stream/${var.kinesis_streams[var.lambda_key].stream_name}"
    }]
  })
}

# Policy for CloudWatch Logs
resource "aws_iam_role_policy" "lambda_logs_policy" {
  name   = "${var.project_name}-lambda-${var.lambda_key}-logs-policy"
  role   = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"
    }]
  })
}
 
# Policy for AWS Secrets Manager access (retrieve OpenSky credentials)
resource "aws_iam_role_policy" "lambda_secrets_manager_policy" {
  count  = var.lambda_config.requires_opensky_credentials ? 1 : 0
  name   = "${var.project_name}-lambda-${var.lambda_key}-secrets-policy"
  role   = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue"
      ]
      Resource = var.opensky_secret_arn
    }]
  })
}

# Policy for VPC access (if applicable)
resource "aws_iam_role_policy_attachment" "lambda_vpc_execution" {
  count              = var.enable_vpc ? 1 : 0
  role               = aws_iam_role.lambda_role.name
  policy_arn         = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Policy for Lambda Insights (if enabled)
resource "aws_iam_role_policy_attachment" "lambda_insights_policy" {
  count              = var.enable_lambda_insights ? 1 : 0
  role               = aws_iam_role.lambda_role.name
  policy_arn         = "arn:aws:iam::aws:policy/CloudWatchLambdaInsightsExecutionRolePolicy"
}


# Policy to allow Lambda to read the secret
resource "aws_secretsmanager_secret_policy" "opensky_credentials" {
  
  secret_arn = var.opensky_secret_arn
  # secret_arn = aws_secretsmanager_secret.opensky_credentials.arn
  # secret_arn = module.secrets_manager.secret_arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaReadSecret"
        Effect = "Allow"
        Principal = {
          # AWS = [for k, v in module.lambda_ingest : v.lambda_role_arn] 
          AWS = [aws_iam_role.lambda_role.arn]
        }
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        # Resource = aws_secretsmanager_secret.opensky_credentials.arn
        # Resource = module.secrets_manager.secret_arn
        Resource = var.opensky_secret_arn
      }
    ]
  })
  depends_on = [aws_iam_role.lambda_role]
}