# ---------------------------------------------------------------------------
# Secrets Manager — RDS PostgreSQL credentials for DMS source endpoint
# The secret is created empty; setup-env.sh populates it from .env values
# after apply, so credentials never appear in Terraform state or HCL.
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "rds_credentials" {
  name                    = "${var.project_name}-dms-rds-credentials"
  description             = "RDS PostgreSQL credentials for DMS source endpoint"
  recovery_window_in_days = 7

  tags = merge(var.tags, {
    Name = "${var.project_name}-dms-rds-credentials"
  })
}

# ---------------------------------------------------------------------------
# DMS subnet group
# ---------------------------------------------------------------------------
resource "aws_dms_replication_subnet_group" "this" {
  replication_subnet_group_id          = "${var.project_name}-dms-subnet-group"
  replication_subnet_group_description = "DMS subnet group for ${var.project_name}"
  subnet_ids                           = var.subnet_ids

  tags = merge(var.tags, {
    Name = "${var.project_name}-dms-subnet-group"
  })
}

# ---------------------------------------------------------------------------
# DMS replication instance
# ---------------------------------------------------------------------------
resource "aws_dms_replication_instance" "this" {
  replication_instance_id     = "${var.project_name}-dms-replication-instance"
  replication_instance_class  = var.replication_instance_class
  allocated_storage           = var.replication_storage_gb
  engine_version              = var.replication_engine_version

  vpc_security_group_ids      = [aws_security_group.dms.id]
  replication_subnet_group_id = aws_dms_replication_subnet_group.this.replication_subnet_group_id

  publicly_accessible         = false
  multi_az                    = false
  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = true
  apply_immediately           = true

  kms_key_arn = aws_kms_key.dms.arn

  # Ensure dms-vpc-role and its policies are fully propagated
  # before DMS attempts to use them. DMS validates the role at creation time.
  depends_on = [
    aws_iam_role_policy_attachment.dms_vpc,
    aws_iam_role_policy.dms_vpc_ec2
  ]

  tags = merge(var.tags, {
    Name = "${var.project_name}-dms-replication-instance"
  })
}

# ---------------------------------------------------------------------------
# DMS security group
# ---------------------------------------------------------------------------
resource "aws_security_group" "dms" {
  name        = "${var.project_name}-dms-sg"
  description = "Security group for DMS replication instance"
  vpc_id      = var.vpc_id

  # ---------------------------------------------------------------
  # Ingress — apenas do security group do RDS PostgreSQL (porta 5432)
  # O DMS conecta-se ao RDS como origem; esta regra permite que o RDS
  # se comunique de volta com o DMS para health checks e replicação.
  # ---------------------------------------------------------------
  ingress {
    from_port       = var.rds_port
    to_port         = var.rds_port
    protocol        = "tcp"
    security_groups = [var.rds_security_group_id]
    description     = "Allow inbound from RDS PostgreSQL security group"
  }

  # ---------------------------------------------------------------
  # Egress — HTTPS para AWS Services (S3, CloudWatch, Secrets Mgr, KMS)
  # Secrets Manager tem VPC Interface Endpoint (PrivateLink). S3,
  # CloudWatch e KMS usam internet mas não há rota válida (IGW descarta
  # tráfego de instâncias sem IP público). O tráfego é criptografado.
  # ---------------------------------------------------------------
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS outbound to AWS services (S3, CloudWatch, Secrets Manager, KMS)"
  }

  # ---------------------------------------------------------------
  # Egress — PostgreSQL para o CIDR do VPC (RDS source)
  # ---------------------------------------------------------------
  egress {
    from_port   = var.rds_port
    to_port     = var.rds_port
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.this.cidr_block]
    description = "Allow outbound to RDS PostgreSQL"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-dms-sg"
  })
}

# ---------------------------------------------------------------------------
# DMS source endpoint — RDS PostgreSQL
# ---------------------------------------------------------------------------
resource "aws_dms_endpoint" "source" {
  endpoint_id   = "${var.project_name}-dms-source-postgres"
  endpoint_type = "source"
  engine_name   = "postgres"
  database_name = var.rds_db_name
  ssl_mode      = "require"

  secrets_manager_access_role_arn = aws_iam_role.dms_s3.arn
  secrets_manager_arn             = aws_secretsmanager_secret.rds_credentials.arn

  postgres_settings {
    capture_ddls           = true
    # PostgreSQL logical replication slot name: hyphens not allowed by DMS
    slot_name              = "${replace(var.project_name, "-", "_")}_dms_slot"
    fail_tasks_on_lob_truncation = false
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-dms-source-postgres"
  })
}

# ---------------------------------------------------------------------------
# DMS target endpoint — S3 Parquet on landing bucket
# ---------------------------------------------------------------------------
resource "aws_dms_s3_endpoint" "target" {
  endpoint_id                      = "${var.project_name}-dms-target-s3"
  endpoint_type                    = "target"
  service_access_role_arn          = aws_iam_role.dms_s3.arn
  bucket_name                      = var.landing_bucket_name
  bucket_folder                    = "dms/${var.rds_db_name}/"
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
# DMS replication task — full load + CDC
# ---------------------------------------------------------------------------
resource "aws_dms_replication_task" "this" {
  replication_task_id        = "${var.project_name}-dms-task"
  replication_instance_arn   = aws_dms_replication_instance.this.replication_instance_arn
  source_endpoint_arn        = aws_dms_endpoint.source.endpoint_arn
  target_endpoint_arn        = aws_dms_s3_endpoint.target.endpoint_arn
  migration_type             = "full-load-and-cdc"

  table_mappings             = var.table_mappings != null ? var.table_mappings : jsonencode({
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

  replication_task_settings = var.dms_task_settings != null ? var.dms_task_settings : jsonencode({
    TargetMetadata = {
      # LOB settings — supported for S3 target
      SupportLobs         = true
      FullLobMode         = false
      LimitedSizeLobMode  = true
      LobMaxSize          = 32
      LobChunkSize        = 64
      InlineLobMaxSize    = 0
      LoadMaxFileSize     = 0
    }
    FullLoadSettings = {
      TargetTablePrepMode             = "DO_NOTHING"
      StopTaskCachedChangesNotApplied = true
      StopTaskCachedChangesApplied    = true
      MaxFullLoadSubTasks             = 8
    }
    Logging = {
      EnableLogging = true
      LogComponents = [
        {
          Id = "TRANSFORMATION"
          Severity = "LOGGER_SEVERITY_DEFAULT"
        },
        {
          Id = "SOURCE_UNLOAD"
          Severity = "LOGGER_SEVERITY_DEFAULT"
        },
        {
          Id = "IO"
          Severity = "LOGGER_SEVERITY_DEFAULT"
        },
        {
          Id = "TARGET_LOAD"
          Severity = "LOGGER_SEVERITY_DEFAULT"
        },
        {
          Id = "PERFORMANCE"
          Severity = "LOGGER_SEVERITY_DEFAULT"
        },
        {
          Id = "SOURCE_CAPTURE"
          Severity = "LOGGER_SEVERITY_DEFAULT"
        },
        {
          Id = "DATA_STRUCTURE"
          Severity = "LOGGER_SEVERITY_DEFAULT"
        }
      ]
    }
  })

  start_replication_task = false

  tags = merge(var.tags, {
    Name = "${var.project_name}-dms-task"
  })

  lifecycle {
    ignore_changes = [
      replication_task_settings
    ]
  }
}

# ---------------------------------------------------------------------------
# Allow DMS to access RDS PostgreSQL on port 5432
# ---------------------------------------------------------------------------
resource "aws_security_group_rule" "dms_to_rds" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.dms.id
  security_group_id        = var.rds_security_group_id
  description              = "DMS replication instance to RDS PostgreSQL"
}

# ---------------------------------------------------------------------------
# CloudWatch log group for DMS
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "dms" {
  name              = "/aws/dms/${var.project_name}"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "${var.project_name}-dms-log-group"
  })
}

# ---------------------------------------------------------------------------
# VPC Endpoint — Secrets Manager (Interface via PrivateLink)
# O DMS precisa acessar o Secrets Manager para buscar as credenciais do RDS.
# O Secrets Manager em us-east-1 só suporta Interface endpoint (não Gateway).
# ---------------------------------------------------------------------------
resource "aws_security_group" "secrets_endpoint" {
  name        = "${var.project_name}-dms-secrets-vpce-sg"
  description = "Security group for Secrets Manager VPC Endpoint"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.dms.id]
    description     = "Allow HTTPS from DMS replication instance"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-dms-secrets-vpce-sg"
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
    Name = "${var.project_name}-dms-secrets-vpce"
  })
}

# ---------------------------------------------------------------------------
# VPC Endpoint — S3 (Gateway — gratuito)
# O DMS precisa escrever os dados de replicação no bucket S3 de destino.
# Gateway Endpoint é gratuito e não requer Security Group nem subnets.
# ---------------------------------------------------------------------------
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type  = "Gateway"

  route_table_ids   = data.aws_route_tables.dms.ids

  tags = merge(var.tags, {
    Name = "${var.project_name}-dms-s3-vpce"
  })
}
