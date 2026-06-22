# ---------------------------------------------------------------------------
# Data sources
# ---------------------------------------------------------------------------
data "aws_vpc" "this" {
  id = var.vpc_id
}

# ---------------------------------------------------------------------------
# Secrets Manager — Aurora PostgreSQL credentials for DMS source endpoint
# O secret é criado pelo setup-env.sh (via AWS CLI) antes do apply.
# O Terraform apenas lê o secret existente — não gerencia ciclo de vida.
# ---------------------------------------------------------------------------
data "aws_secretsmanager_secret" "aurora_credentials" {
  name = "${var.project_name}-dms-aurora-credentials"
}

# ---------------------------------------------------------------------------
# DMS subnet group (DMS Serverless também precisa)
# ---------------------------------------------------------------------------
resource "aws_dms_replication_subnet_group" "this" {
  replication_subnet_group_id          = "${var.project_name}-dms-serverless-subnet-group"
  replication_subnet_group_description = "DMS Serverless subnet group for ${var.project_name}"
  subnet_ids                           = var.subnet_ids

  # DMS requires the dms-vpc-role to exist before creating subnet groups
  depends_on = [aws_iam_role.dms_vpc_default]

  tags = merge(var.tags, {
    Name = "${var.project_name}-dms-serverless-subnet-group"
  })
}

# ---------------------------------------------------------------------------
# DMS security group
# ---------------------------------------------------------------------------
resource "aws_security_group" "dms" {
  name        = "${var.project_name}-dms-serverless-sg"
  description = "Security group for DMS Serverless"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = var.aurora_port
    to_port         = var.aurora_port
    protocol        = "tcp"
    security_groups = [var.aurora_security_group_id]
    description     = "Allow inbound from Aurora PostgreSQL security group"
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS outbound to AWS services (S3, CloudWatch, Secrets Manager, KMS)"
  }

  egress {
    from_port   = var.aurora_port
    to_port     = var.aurora_port
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.this.cidr_block]
    description = "Allow outbound to Aurora PostgreSQL"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-dms-serverless-sg"
  })
}

# ---------------------------------------------------------------------------
# IAM roles for DMS
# ---------------------------------------------------------------------------
resource "aws_iam_role" "dms_s3" {
  name = "${var.project_name}-dms-serverless-s3-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "dms.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "dms_s3" {
  name = "${var.project_name}-dms-serverless-s3-policy"
  role = aws_iam_role.dms_s3.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect = "Allow"
          Action = [
            "s3:PutObject",
            "s3:GetObject",
            "s3:DeleteObject",
            "s3:ListBucket",
            "s3:GetBucketLocation",
          ]
          Resource = [
            "arn:aws:s3:::${var.landing_bucket_name}",
            "arn:aws:s3:::${var.landing_bucket_name}/*",
          ]
        },
        {
          Effect = "Allow"
          Action = [
            "secretsmanager:GetSecretValue",
          ]
          Resource = [data.aws_secretsmanager_secret.aurora_credentials.arn]
        },
      ],
      var.kms_key_arn != null ? [
        {
          Effect = "Allow"
          Action = [
            "kms:Decrypt",
            "kms:Encrypt",
            "kms:GenerateDataKey",
          ]
          Resource = [var.kms_key_arn]
        },
      ] : []
    )
  })
}

# The default dms-vpc-role that DMS expects for VPC management
resource "aws_iam_role" "dms_vpc_default" {
  name = "dms-vpc-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "dms.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "dms_vpc_default" {
  role       = aws_iam_role.dms_vpc_default.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
}

# ---------------------------------------------------------------------------
# DMS source endpoint — Aurora PostgreSQL
# ---------------------------------------------------------------------------
resource "aws_dms_endpoint" "source" {
  endpoint_id   = "${var.project_name}-dms-source-aurora"
  endpoint_type = "source"
  engine_name   = "aurora-postgresql"
  database_name = var.aurora_db_name
  ssl_mode      = "require"

  secrets_manager_access_role_arn = aws_iam_role.dms_s3.arn
  secrets_manager_arn             = data.aws_secretsmanager_secret.aurora_credentials.arn

  postgres_settings {
    capture_ddls                  = true
    # pglogical — plugin de replicação lógica para CDC no Aurora PostgreSQL
    plugin_name                   = "pglogical"
    fail_tasks_on_lob_truncation  = false
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-dms-source-aurora"
  })
}

# ---------------------------------------------------------------------------
# DMS target endpoint — S3 Parquet on landing bucket
# ---------------------------------------------------------------------------
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = var.vpc_id
  service_name = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  
  route_table_ids = [data.aws_vpc.this.main_route_table_id]
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-s3-vpce"
  })
}

resource "aws_dms_s3_endpoint" "target" {
  endpoint_id                      = "${var.project_name}-dms-target-s3"
  endpoint_type                    = "target"
  service_access_role_arn          = aws_iam_role.dms_s3.arn
  bucket_name                      = var.landing_bucket_name
  bucket_folder                    = "dms/${var.aurora_db_name}/"
  data_format                      = "parquet"
  parquet_version                  = "parquet-2-0"
  compression_type                 = "gzip"
  date_partition_enabled           = true
  date_partition_sequence          = "YYYYMMDD"
  include_op_for_full_load         = true
  cdc_path                         = "cdc/"
  cdc_max_batch_interval           = 60
  timestamp_column_name            = "dms_timestamp"
  preserve_transactions            = false
  glue_catalog_generation          = false

  tags = merge(var.tags, {
    Name = "${var.project_name}-dms-target-s3"
  })
}

# ---------------------------------------------------------------------------
# DMS Serverless replication config — full load + CDC
# ---------------------------------------------------------------------------
resource "aws_dms_replication_config" "this" {
  replication_config_identifier      = "${var.project_name}-dms-serverless-config"
  source_endpoint_arn                 = aws_dms_endpoint.source.endpoint_arn
  target_endpoint_arn                 = aws_dms_s3_endpoint.target.endpoint_arn
  replication_type                    = "full-load-and-cdc"

  compute_config {
    replication_subnet_group_id  = aws_dms_replication_subnet_group.this.replication_subnet_group_id
    vpc_security_group_ids       = [aws_security_group.dms.id]
    max_capacity_units           = var.max_capacity_units
    min_capacity_units           = var.min_capacity_units
    multi_az                     = var.multi_az
    preferred_maintenance_window = "sun:06:00-sun:07:00"
  }

  table_mappings = var.table_mappings != null ? var.table_mappings : jsonencode({
    rules = [
      {
        "rule-type"     = "selection"
        "rule-id"       = "1"
        "rule-name"     = "default"
        "object-locator" = {
          "schema-name" = "%"
          "table-name"  = "%"
        }
        "rule-action"   = "include"
      }
    ]
  })

  replication_settings = var.replication_settings != null ? var.replication_settings : jsonencode({
    TargetMetadata = {
      SupportLobs         = true
      FullLobMode         = false
      LimitedSizeLobMode  = true
      LobMaxSize          = 32
      LobChunkSize        = 64
      InlineLobMaxSize    = 0
      LoadMaxFileSize     = 0
    }
    ErrorBehavior = {
      FailOnNoTablesCaptured = false
    }
    FullLoadSettings = {
      TargetTablePrepMode             = "DO_NOTHING"
      StopTaskCachedChangesNotApplied = false
      StopTaskCachedChangesApplied    = false
      MaxFullLoadSubTasks             = 8
    }
    Logging = {
      EnableLogging = true
      LogComponents = [
        { Id = "TRANSFORMATION",  Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "SOURCE_UNLOAD",   Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "IO",              Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "TARGET_LOAD",     Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "PERFORMANCE",    Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "SOURCE_CAPTURE", Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "SORTER",         Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "REST_SERVER",    Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "VALIDATOR_EXT",  Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "TARGET_APPLY",   Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "TASK_MANAGER",   Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "TABLES_MANAGER", Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "METADATA_MANAGER", Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "FILE_FACTORY",   Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "COMMON",         Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "ADDONS",         Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "DATA_STRUCTURE", Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "COMMUNICATION",  Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "FILE_TRANSFER",  Severity = "LOGGER_SEVERITY_DEFAULT" }
      ]
    }
  })

  # Don't auto-start — use AWS Console or CLI to start after validation
  start_replication = false

  tags = merge(var.tags, {
    Name = "${var.project_name}-dms-serverless-config"
  })
}

# ---------------------------------------------------------------------------
# Allow DMS to access Aurora PostgreSQL on port 5432
# ---------------------------------------------------------------------------
resource "aws_security_group_rule" "dms_to_aurora" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.dms.id
  security_group_id        = var.aurora_security_group_id
  description              = "DMS Serverless to Aurora PostgreSQL"
}

# ---------------------------------------------------------------------------
# CloudWatch log group for DMS Serverless
# DMS Serverless cria logs em dms-replication-config-<config-id> automaticamente
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "dms" {
  name              = "dms-replication-config-${var.project_name}-dms-serverless-config"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "${var.project_name}-dms-serverless-log-group"
  })
}

# ---------------------------------------------------------------------------
# VPC Endpoint — Secrets Manager (Interface via PrivateLink)
# DMS precisa acessar o Secrets Manager para credenciais do Aurora
# ---------------------------------------------------------------------------
resource "aws_security_group" "secrets_endpoint" {
  name        = "${var.project_name}-dms-serverless-secrets-vpce-sg"
  description = "Security group for Secrets Manager VPC Endpoint (DMS Serverless)"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.dms.id]
    description     = "Allow HTTPS from DMS Serverless"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-dms-serverless-secrets-vpce-sg"
  })
}

resource "aws_vpc_endpoint" "secrets_manager" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.secretsmanager"
  vpc_endpoint_type   = "Interface"

  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.secrets_endpoint.id]

  private_dns_enabled = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-dms-serverless-secrets-vpce"
  })
}

# ---------------------------------------------------------------------------
# KMS Key for DMS encryption
# ---------------------------------------------------------------------------
resource "aws_kms_key" "dms" {
  description             = "KMS key for DMS Serverless ${var.project_name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = var.tags
}

resource "aws_kms_alias" "dms" {
  name          = "alias/${var.project_name}-dms-serverless"
  target_key_id = aws_kms_key.dms.key_id
}
