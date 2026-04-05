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

# Kinesis Stream
variable "kinesis_stream_name" {
  description = "Nome do Kinesis Stream"
  type        = string
}

variable "kinesis_stream_arn" {
  description = "ARN do Kinesis Stream"
  type        = string
}

# Kinesis Firehose - S3
variable "firehose_s3_name" {
  description = "Nome do Firehose com destino S3"
  type        = string
  default     = ""
}

variable "firehose_s3_arn" {
  description = "ARN do Firehose com destino S3"
  type        = string
  default     = ""
}

# Kinesis Firehose - OpenSearch
variable "firehose_opensearch_name" {
  description = "Nome do Firehose com destino OpenSearch"
  type        = string
  default     = ""
}

variable "firehose_opensearch_arn" {
  description = "ARN do Firehose com destino OpenSearch"
  type        = string
  default     = ""
}

# Lambda Functions
variable "lambda_functions" {
  description = "Lista de funções Lambda para monitorar"
  type = list(object({
    name = string
    arn  = string
  }))
  default = []
}

# =============================================================================
# OPENSEARCH SERVERLESS (ATUALIZADO)
# =============================================================================
variable "opensearch_type" {
  description = "Tipo: 'cluster' ou 'serverless'"
  type        = string
  default     = "serverless"
  
  validation {
    condition     = contains(["cluster", "serverless"], var.opensearch_type)
    error_message = "opensearch_type must be either 'cluster' or 'serverless'."
  }
}

variable "opensearch_domain_name" {
  description = "Nome do domínio OpenSearch (para cluster provisionado)"
  type        = string
  default     = ""
}

variable "opensearch_domain_arn" {
  description = "ARN do domínio OpenSearch (para cluster provisionado)"
  type        = string
  default     = ""
}

variable "opensearch_collection_name" {
  description = "Nome da collection OpenSearch Serverless"
  type        = string
  default     = ""
}

variable "opensearch_collection_arn" {
  description = "ARN da collection OpenSearch Serverless"
  type        = string
  default     = ""
}

# S3 Bucket
variable "s3_bucket_name" {
  description = "Nome do bucket S3 de destino"
  type        = string
  default     = ""
}

# Thresholds configuráveis
variable "alarm_thresholds" {
  description = "Thresholds personalizáveis para alarmes"
  type = object({
    kinesis_iterator_age_ms           = number
    kinesis_no_records_minutes        = number
    kinesis_write_throttle_percent    = number
    kinesis_read_throttle_percent     = number
    firehose_delivery_failure_percent = number
    firehose_incoming_records_low     = number
    lambda_error_percent              = number
    lambda_duration_p95_ms            = number
    lambda_throttle_count             = number
    opensearch_ocu_utilization        = number  # ✅ Serverless
    opensearch_cpu_percent            = number  # ✅ Cluster
    opensearch_jvm_memory_percent     = number  # ✅ Cluster
    opensearch_indexing_failures      = number
  })
  default = {
    kinesis_iterator_age_ms           = 60000
    kinesis_no_records_minutes        = 10
    kinesis_write_throttle_percent    = 5
    kinesis_read_throttle_percent     = 5
    firehose_delivery_failure_percent = 10
    firehose_incoming_records_low     = 1
    lambda_error_percent              = 5
    lambda_duration_p95_ms            = 5000
    lambda_throttle_count             = 10
    opensearch_ocu_utilization        = 80    # ✅ Serverless
    opensearch_cpu_percent            = 80    # ✅ Cluster
    opensearch_jvm_memory_percent     = 85    # ✅ Cluster
    opensearch_indexing_failures      = 5
  }
}

variable "alarm_evaluation_periods" {
  description = "Períodos de avaliação para alarmes"
  type        = number
  default     = 2
}

variable "alarm_period_seconds" {
  description = "Período em segundos para avaliação de métricas"
  type        = number
  default     = 300
}

variable "sns_alarm_topic_arn" {
  description = "ARN do tópico SNS para notificações de alarme"
  type        = string
  default     = ""
}

variable "alerts_email" {
  description = "Email para receber notificações de alarme"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for email in var.alerts_email : can(regex("^[\\w-\\.]+@([\\w-]+\\.)+[\\w-]{2,4}$", email))
    ])
    error_message = "Todos os emails devem ser válidos."
  }
}

variable "dash_user_arns" {
  description = "Lista de ARNs dos usuários IAM com acesso ao OpenSearch Dashboards"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for arn in var.dash_user_arns : can(regex("^arn:aws:iam::[0-9]{12}:user/.+$", arn))
    ])
    error_message = "Todos os ARNs devem ser válidos e seguir o formato de usuário IAM."
  }
}