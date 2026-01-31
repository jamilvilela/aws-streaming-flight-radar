resource "aws_kinesisanalyticsv2_application" "flight_processor" {
  name = "${var.project_name}-flights-enrichment"

  runtime_environment = "FLINK-1_15"
  service_execution_role = aws_iam_role.analytics_role.arn

  application_configuration {
    application_code_configuration {
      code_content_type = "ZIPFILE"
      s3_content_location {
        bucket_arn = aws_s3_bucket.code_bucket.arn
        file_key   = "flink-app.jar"
      }
    }

    # Otimizações para alto throughput
    flink_application_configuration {
      parallelism_configuration {
        configuration_type = "CUSTOM"
        parallelism       = 10
        parallelism_per_kpu = 4
        auto_scaling_enabled = true
      }
    }
  }
}