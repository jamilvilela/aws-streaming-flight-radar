# ============================================================================
# Redshift Serverless Data Warehouse
# ============================================================================
# Receives enriched flight data from KDA Flink
# Provides SQL analytics interface for QuickSight/BI tools
# ============================================================================

# ============================================================================
# Redshift Serverless Namespace
# ============================================================================

resource "aws_redshiftserverless_namespace" "flight_data" {
  namespace_name      = "${var.project_name}-redshift"
  db_name             = var.database_name
  admin_user_password = var.admin_password
  admin_username      = var.admin_username
  iam_roles           = [aws_iam_role.redshift_role.arn]
  log_exports         = ["connectionlog", "useractivitylog", "userlog"]

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-redshift-namespace"
      Environment = var.environment
    }
  )

  depends_on = [aws_iam_role_policy_attachment.redshift_s3_access]
}

# ============================================================================
# Redshift Serverless Workgroup
# ============================================================================

resource "aws_redshiftserverless_workgroup" "flight_data" {
  namespace_name       = aws_redshiftserverless_namespace.flight_data.namespace_name
  workgroup_name       = "${var.project_name}-workgroup"
  base_capacity        = var.base_capacity  # Default: 32 RPUs
  max_capacity         = var.max_capacity   # Default: 512 RPUs
  subnet_ids           = var.subnet_ids
  security_group_ids   = [aws_security_group.redshift_sg.id]
  publicly_accessible  = var.publicly_accessible
  enhanced_vpc_routing = var.enhanced_vpc_routing

  config {
    incremental_backup_retention_period = var.backup_retention_days
    log_exports                         = ["connectionlog", "useractivitylog", "userlog"]
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-redshift-workgroup"
      Environment = var.environment
    }
  )
}

# ============================================================================
# Security Group for Redshift
# ============================================================================

resource "aws_security_group" "redshift_sg" {
  name        = "${var.project_name}-redshift-sg"
  description = "Security group for Redshift Serverless"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 5439  # Redshift default port
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "Redshift database access"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-redshift-sg"
      Environment = var.environment
    }
  )
}

# ============================================================================
# IAM Role for Redshift
# ============================================================================

resource "aws_iam_role" "redshift_role" {
  name               = "${var.project_name}-redshift-role"
  assume_role_policy = data.aws_iam_policy_document.redshift_assume_role.json

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-redshift-role"
      Environment = var.environment
    }
  )
}

resource "aws_iam_role_policy_attachment" "redshift_s3_access" {
  role       = aws_iam_role.redshift_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_iam_role_policy" "redshift_custom_policy" {
  name   = "${var.project_name}-redshift-custom-policy"
  role   = aws_iam_role.redshift_role.id
  policy = data.aws_iam_policy_document.redshift_custom_policy.json
}

# ============================================================================
# CloudWatch Log Group for Redshift Logs
# ============================================================================

resource "aws_cloudwatch_log_group" "redshift_logs" {
  name              = "/aws/redshift-serverless/${var.project_name}"
  retention_in_days = var.log_retention_days

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-redshift-logs"
      Environment = var.environment
    }
  )
}

# ============================================================================
# Redshift Parameter Group for Configuration
# ============================================================================

resource "aws_redshiftserverless_workgroup_parameter_group" "flight_data" {
  count                = var.create_parameter_group ? 1 : 0
  workgroup_name       = aws_redshiftserverless_workgroup.flight_data.workgroup_name
  parameter_group_name = "${var.project_name}-params"
}
