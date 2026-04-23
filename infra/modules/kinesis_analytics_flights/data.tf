# Cria o zip dos 3 scripts SQL
data "archive_file" "flink_sql_zip" {
  type        = "zip"
  output_path = "${path.module}/flink_sql_app.zip"

  source {
    content  = var.sql_source_script
    filename = "sql/01_source.sql"
  }

  source {
    content  = var.sql_enriched_script
    filename = "sql/02_enriched_view.sql"
  }

  source {
    content  = var.sql_sinks_script
    filename = "sql/03_sinks_kinesis.sql"
  }
}