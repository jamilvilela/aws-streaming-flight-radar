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
  auto_minor_version_upgrade  = false
  allow_major_version_upgrade = false
  apply_immediately           = true

  kms_key_arn = aws_kms_key.dms.arn

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

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "DMS internal traffic"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
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
  port          = var.rds_port
  server_name   = var.rds_endpoint
  ssl_mode      = "require"

  secrets_manager_access_role_arn = aws_iam_role.dms_s3.arn
  secrets_manager_arn             = aws_secretsmanager_secret.rds_credentials.arn

  postgres_settings {
    capture_ddls           = true
    slot_name              = "${var.project_name}_dms_slot"
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
  bucket_folder                    = "dms/flights/"
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
  glue_catalog_generation          = true

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
        rule_type     = "selection"
        rule_id       = "1"
        rule_name     = "default"
        object_locator = {
          schema_name = "%"
          table_name  = "%"
        }
        rule_action   = "include"
      }
    ]
  })

  replication_task_settings = var.dms_task_settings != null ? var.dms_task_settings : jsonencode({
    TargetMetadata = {
      TargetSchema = ""
      SupportLobs = true
      FullLobMode = false
      LobChunkSize = 64
      LimitedSizeLobMode = true
      LobMaxSize = 32
      InlineLobMaxSize = 0
      LoadMaxFileSize = 0
      ParallelLoadThreads = 8
      ParallelLoadBufferSize = 50
      BatchApplyEnabled = false
      TaskRecoveryTableEnabled = true
      ParallelApplyThreads = 0
      ParallelApplyBufferSize = 0
      FullLoadTransactionSize = 10000
      CharLengthSemantics = "BYTE"
    }
    FullLoadSettings = {
      TargetTablePrepMode = "DO_NOTHING"
      CreatePkAfterFullLoad = false
      StopTaskCachedChangesNotApplied = false
      StopTaskCachedChangesApplied = false
      MaxFullLoadSubTasks = 8
      TransactionConsistencyTimeout = 600
      CommitRate = 10000
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
          Id = "TASK_RECOVERY"
          Severity = "LOGGER_SEVERITY_DEFAULT"
        },
        {
          Id = "RESTART"
          Severity = "LOGGER_SEVERITY_DEFAULT"
        },
        {
          Id = "TASK_PROGRESS"
          Severity = "LOGGER_SEVERITY_DEFAULT"
        },
        {
          Id = "DATA_STRUCTURE"
          Severity = "LOGGER_SEVERITY_DEFAULT"
        }
      ]
    }
    BeforeImageSettings = {
      EnableBeforeImage = true
      FieldName = "dms_before_image"
      ColumnFilter = "pk-only"
    }
    ChangeProcessingDdlHandlingPolicy = {
      HandleSourceTableDropped = false
      HandleSourceTableTruncated = true
      HandleSourceTableAltered = true
    }
    ControlTablesettings = {
      historyTimeslotInMinutes = 5
      ControlSchema = "dms_control"
      HistoryTimeslotInMinutes = 5
      StatusIntervalInMinutes = 1
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
