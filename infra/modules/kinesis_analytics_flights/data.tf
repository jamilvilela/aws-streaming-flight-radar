data "archive_file" "flink_sql_zip" {
  type        = "zip"
  output_path = "${path.module}/flink_sql_app.zip"
  source_dir  = "${path.root}/../app/flink-sql-application"
  excludes    = ["deploy_flink_sql.sh", "README.md", "QUICK_START.md"]
}