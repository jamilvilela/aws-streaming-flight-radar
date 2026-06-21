variable "project_name" {
  description = "Nome do projeto para prefixar recursos"
  type        = string
}

variable "aws_region" {
  description = "Região AWS para os recursos"
  type        = string
}

variable "environment" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
}

variable "tags" {
  description = "Tags para recursos"
  type        = map(string)
  default     = {}
}

# =============================================================================
# API Gateway
# =============================================================================
variable "api_gateway_stage" {
  description = "Nome do stage do API Gateway (ex: prod)"
  type        = string
  default     = ""
}

# =============================================================================
# Lambda Functions
# =============================================================================
variable "lambda_functions" {
  description = "Lista de funções Lambda para monitorar"
  type = list(object({
    name = string
    arn  = string
  }))
  default = []
}

# =============================================================================
# Kinesis Streams
# =============================================================================
variable "kinesis_stream_name" {
  description = "Nome do Kinesis Stream principal (flights)"
  type        = string
  default     = ""
}

variable "kinesis_stream_name_rt" {
  description = "Nome do Kinesis Stream secundário (flights_rt - enriched)"
  type        = string
  default     = ""
}

# =============================================================================
# Kinesis Data Analytics (Flink)
# =============================================================================
variable "kda_application_name" {
  description = "Nome da aplicação Kinesis Data Analytics (Flink)"
  type        = string
  default     = ""
}

# =============================================================================
# DMS
# =============================================================================
variable "dms_task_id" {
  description = "ID da tarefa de replicação DMS"
  type        = string
  default     = ""
}

# =============================================================================
# SQS
# =============================================================================
variable "sqs_queue_name" {
  description = "Nome da fila SQS (DLQ)"
  type        = string
  default     = ""
}

# =============================================================================
# S3 - Landing Bucket
# =============================================================================
variable "s3_landing_bucket_name" {
  description = "Nome do bucket S3 de destino (landing) para métricas DMS"
  type        = string
  default     = ""
}

# variable "opensearch_collection_arn" {
#   description = "ARN da collection OpenSearch Serverless"
#   type        = string
#   default     = ""
