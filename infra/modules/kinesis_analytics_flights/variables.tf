variable "project_name" {
  description = "Nome do projeto"
  type        = string
}

variable "environment" {
  description = "Environment (production, staging, development)"
  type        = string
  default     = "production"
}

variable "region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "kinesis_stream_arn" {
  description = "ARN do Kinesis Stream de origem para aplicação Flink"
  type        = string
}

variable "sink_kinesis_stream_arn" {
  description = "ARN do Kinesis Stream de destino (kinesis_stream_flights_rt para Redshift)"
  type        = string
}

variable "sql_source_script" {
  description = "Conteúdo do script SQL 01_source.sql (TABLE SOURCE)"
  type        = string
  default     = ""
}

variable "sql_enriched_script" {
  description = "Conteúdo do script SQL 02_enriched_view.sql (VIEW enrichment)"
  type        = string
  default     = ""
}

variable "sql_sinks_script" {
  description = "Conteúdo do script SQL 03_sinks_kinesis.sql (4 OUTPUT SINKS)"
  type        = string
  default     = ""
}

variable "input_parallelism" {
  description = "Paralelismo de entrada do aplicativo Flink"
  type        = number
  default     = 1
}

variable "auto_start_application" {
  description = "Auto-iniciar aplicação Flink após criar recurso"
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "CloudWatch log retention em dias"
  type        = number
  default     = 7
}

variable "sns_topic_arn" {
  description = "ARN do SNS Topic para receber alertas do KDA"
  type        = string
  default     = ""
}

variable "create_cloudwatch_alarms" {
  description = "Criar CloudWatch alarms para o KDA"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags a serem aplicadas aos recursos"
  type        = map(string)
  default     = {}
}

variable "s3_artifacts_bucket" {
  description = "S3 bucket para armazenar artefatos do Flink (JAR, SQL)"
  type        = string
}

variable "s3_landing_bucket" {
  description = "S3 bucket para saída dos dados processados pelo Flink"
  type        = string
}