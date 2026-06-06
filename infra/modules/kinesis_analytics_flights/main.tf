# AWS Kinesis Data Analytics V2 (Apache Flink) para processar stream de voos
# Recebe dados do kinesis_stream_flights e envia dados enriquecidos ao S3 Landing


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

# JAR do connector Kinesis - sobe para S3
resource "aws_s3_object" "kinesis_connector_jar" {
  bucket = var.s3_artifacts_bucket
  key    = "lib/flink-sql-connector-aws-kinesis-streams-5.0.0-1.20.jar"
  source = "${path.root}/../app/flink-sql-application/lib/flink-sql-connector-aws-kinesis-streams-5.0.0-1.20.jar"
}

# Aplicação Kinesis Data Analytics V2 (Apache Flink)
resource "aws_kinesisanalyticsv2_application" "kda_flights" {
  name                   = "${var.project_name}-kda-flights"
  runtime_environment    = "FLINK-1_20"
  service_execution_role = aws_iam_role.kda_execution.arn
  application_mode       = "STREAMING"
  start_application      = var.auto_start_application

  application_configuration {
    # 1. 01_source.sql - TABLE SOURCE (Kinesis input)
    # 2. 02_enriched_view.sql - VIEW com transformações
    # 3. 03_sinks_s3.sql - 4 Sinks de saída

    application_code_configuration {
      code_content_type = "ZIPFILE"

      code_content {
        s3_content_location {
          bucket_arn = "arn:aws:s3:::${var.s3_artifacts_bucket}"
          file_key   = aws_s3_object.flink_sql_zip.key
        }
      }
    }

    # Configuração específica do Flink
    flink_application_configuration {
      # Checkpoint usando config padrão AWS (evita erros de validação)
      # O bug "Partial recovery not supported" será tratado via
      # restart-strategy=none nas propriedades de ambiente
      checkpoint_configuration {
        configuration_type = "DEFAULT"
      }

      # Monitoramento
      monitoring_configuration {
        configuration_type = "CUSTOM"
        log_level          = "INFO"
        metrics_level      = "TASK"
      }

      # Configuração de paralelismo
      parallelism_configuration {
        configuration_type   = "CUSTOM"
        parallelism          = var.input_parallelism
        parallelism_per_kpu  = 2
        auto_scaling_enabled = true
      }
    }

    # Propriedades de ambiente
    environment_properties {
      property_group {
        property_group_id = "FLINK_APPLICATION_PROPERTIES"

        property_map = {
          AwsRegion          = var.region
          KINESIS_STREAM_ARN = var.kinesis_stream_arn
          AWS_REGION         = var.region

          # CORREÇÃO: Desabilitar restart automático para evitar loop de failover
          # O connector Kinesis tem bug de "partial recovery" - com restart
          # habilitado, a aplicação fica em loop constante de falha
          "restart-strategy" = "none"
        }
      }

      property_group {
        property_group_id = "kinesis.analytics.flink.run.options"

        property_map = {
          python = "app.py"
        }
      }
    }

    # Snapshots automáticos para recuperação de falhas
    application_snapshot_configuration {
      snapshots_enabled = false
    }

    # Configuração de VPC (opcional)
    # vpc_configuration {
    #   subnet_ids         = var.subnet_ids
    #   security_group_ids = var.security_group_ids
    # }
  }

  # Logs do CloudWatch
  cloudwatch_logging_options {
    log_stream_arn = aws_cloudwatch_log_stream.kda_flights_log_stream.arn
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-kda-flights"
      StreamType  = "flights-flink-processing"
      Environment = var.environment
    }
  )

  depends_on = [
    aws_cloudwatch_log_stream.kda_flights_log_stream
  ]
}

