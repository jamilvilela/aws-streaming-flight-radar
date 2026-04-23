# AWS Kinesis Data Analytics V2 (Apache Flink) para processar stream de voos
# Recebe dados do kinesis_stream_flights e envia dados enriquecidos ao kinesis_stream_flights_rt (Redshift)
#
# DEPLOYMENT STRATEGY:
# • DESENVOLVIMENTO LOCAL: use bash script (deploy_flink_sql.sh start)
# • PRODUÇÃO: use Terraform com CI/CD (GitHub Actions)
#
# var.auto_start_application controla se Flink inicia automaticamente:
#   - dev/staging: false (você controla manualmente)
#   - prod: true (via CI/CD, sem intervenção manual)

# Log do CloudWatch para aplicação Flink
resource "aws_cloudwatch_log_group" "kda_flights_log_group" {
  name              = "/aws/kinesisanalytics/${var.project_name}-kda-flights"
  retention_in_days = var.log_retention_days

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-kda-flights-log"
      Environment = var.environment
    }
  )
}

resource "aws_cloudwatch_log_stream" "kda_flights_log_stream" {
  name           = "FlinkApplicationLogs"
  log_group_name = aws_cloudwatch_log_group.kda_flights_log_group.name
}

resource "aws_s3_object" "flink_sql_zip" {
  bucket = var.s3_artifacts_bucket
  key    = "flink/${var.project_name}-kda-flights-${data.archive_file.flink_sql_zip.output_md5}.zip"
  source = data.archive_file.flink_sql_zip.output_path
  etag   = data.archive_file.flink_sql_zip.output_md5
}

# Aplicação Kinesis Data Analytics V2 (Apache Flink)
resource "aws_kinesisanalyticsv2_application" "kda_flights" {
  name                   = "${var.project_name}-kda-flights"
  runtime_environment    = "FLINK-1_19"
  service_execution_role = var.role_arn
  application_mode       = "STREAMING"
  start_application      = var.auto_start_application

  application_configuration {
    # 1. 01_source.sql - TABLE SOURCE (Kinesis input)
    # 2. 02_enriched_view.sql - VIEW com transformações
    # 3. 03_sinks_kinesis.sql - 4 Sinks de saída
    
    application_code_configuration {
      code_content_type = "ZIPFILE"

      code_content {
        s3_content_location {              # ← era text_content
          bucket_arn = "arn:aws:s3:::${var.s3_artifacts_bucket}"
          file_key   = aws_s3_object.flink_sql_zip.key
        }
      }
    }

    # Configuração específica do Flink
    flink_application_configuration {
      # Checkpointing para garantir processamento exatamente uma vez
      checkpoint_configuration {
        configuration_type             = "CUSTOM"
        checkpointing_enabled          = true
        checkpoint_interval            = 60000  # 60 segundos
        min_pause_between_checkpoints  = 5000   # 5 segundos
      }

      # Monitoramento
      monitoring_configuration {
        configuration_type = "CUSTOM"
        log_level          = "INFO"
        metrics_level      = "TASK"
      }

      # Configuração de paralelismo
      parallelism_configuration {
        configuration_type       = "CUSTOM"
        parallelism              = var.input_parallelism
        parallelism_per_kpu      = 2
        auto_scaling_enabled     = true
      }
    }

    # Propriedades de ambiente
    environment_properties {
      property_group {
        property_group_id = "FLINK_APPLICATION_PROPERTIES"

        property_map = {
          AwsRegion = var.region
        }
      }
    }

    # Snapshots automáticos para recuperação de falhas
    application_snapshot_configuration {
      snapshots_enabled = true
    }

    # Configuração de VPC (opcional)
    # vpc_configuration {
    #   subnet_ids         = var.subnet_ids
    #   security_group_ids = var.security_group_ids
    # }
  }

  # Logs do CloudWatch
  # cloudwatch_logging_options {
  #   log_stream_arn = "${aws_cloudwatch_log_group.kda_flights_log_group.arn}:${aws_cloudwatch_log_stream.kda_flights_log_stream.name}"
  # }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-kda-flights"
      StreamType  = "flights-flink-processing"
      Environment = var.environment
    }
  )

  # depends_on = [
  #   aws_cloudwatch_log_stream.kda_flights_log_stream
  # ]
}

# Snapshot manual da aplicação para disaster recovery
resource "aws_kinesisanalyticsv2_application_snapshot" "kda_flights_snapshot" {
  application_name = aws_kinesisanalyticsv2_application.kda_flights.name
  snapshot_name    = "${var.project_name}-kda-flights-backup-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  depends_on = [
    aws_kinesisanalyticsv2_application.kda_flights
  ]
}

# ============================================================================
# DEPLOYMENT NOTES
# ============================================================================
#
# DESENVOLVIMENTO LOCAL (sua máquina):
# ─────────────────────────────────────────────────────────────────────────
# 1. terraform apply -var="auto_start_application=false"
#    → Cria aplicação KDA sem iniciar
#
# 2. bash app/flink-sql-application/deploy_flink_sql.sh start
#    → Inicia via AWS CLI (seu script bash)
#
# 3. Testa dados e monitora
#
# 4. bash app/flink-sql-application/deploy_flink_sql.sh stop
#    → Para quando terminar
#
#
# PRODUÇÃO (via CI/CD):
# ─────────────────────────────────────────────────────────────────────────
# 1. Developer: git push main
#
# 2. GitHub Actions executa:
#    terraform apply -var="auto_start_application=true"
#    → Cria aplicação E inicia automaticamente
#
# 3. GitHub Actions testa data flow
#
# 4. Slack notifica resultado
#
# ============================================================================
