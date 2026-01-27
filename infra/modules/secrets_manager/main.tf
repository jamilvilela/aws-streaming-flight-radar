resource "aws_secretsmanager_secret" "opensky_credentials" {
  name                    = "${var.project_name}-opensky-credentials"
  description             = "OpenSky API credentials for flight radar data ingestion"
  recovery_window_in_days = var.recovery_window_days

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-opensky-credentials"
      Type        = "api-credentials"
      Application = "flight-radar"
    }
  )
}

resource "aws_secretsmanager_secret_version" "opensky_credentials" {
  secret_id = aws_secretsmanager_secret.opensky_credentials.id
  secret_string = jsonencode({
    username = var.opensky_username
    password = var.opensky_password
  })
}

# Policy to allow Lambda to read the secret
resource "aws_secretsmanager_secret_policy" "opensky_credentials" {
  count      = length(var.lambda_role_arns) > 0 ? 1 : 0
  secret_arn = aws_secretsmanager_secret.opensky_credentials.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaReadSecret"
        Effect = "Allow"
        Principal = {
          AWS = var.lambda_role_arns 
        }
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.opensky_credentials.arn
      }
    ]
  })
}

# CloudWatch Log for secret access (optional)
resource "aws_cloudwatch_log_group" "secrets_access_logs" {
  name              = "/aws/secretsmanager/${var.project_name}-opensky"
  retention_in_days = var.log_retention_days

  tags = var.tags
}
