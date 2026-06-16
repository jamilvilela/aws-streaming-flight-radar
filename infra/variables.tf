variable "project_name" { type = string }
variable "aws_region" { type = string }
variable "environment" { type = string }

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

variable "tags" {
  type    = map(string)
  default = {}
}

variable "kinesis_streams" {
  description = "Map of Kinesis stream names and their configurations"
  type = map(object({
    name = string
    mode = string # "ON_DEMAND" ou "PROVISIONED"
  }))
}


variable "lambda_functions" {
  description = "Map of Lambda function configurations"
  type = map(object({
    name              = string
    handler           = string
    runtime           = string
    timeout           = number
    memory_size       = number
    ephemeral_storage = number
    tags              = map(string)
  }))
}

variable "datalake_role_name" {
  description = "Name of the IAM role for datalake analytics"
  type        = string
}

variable "buckets" {
  description = "Map of S3 bucket names for different purposes"
  type        = map(string)
}

variable "databases" {
  description = "Map of Glue database names for different purposes"
  type        = map(string)
}

variable "tables" {
  description = "Map of Glue table names for different purposes"
  type        = map(string)
}

variable "alarm_thresholds" {
  description = "Thresholds personalizáveis para alarmes CloudWatch"
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
  }

  validation {
    condition     = var.alarm_thresholds.kinesis_iterator_age_ms >= 0 && var.alarm_thresholds.kinesis_iterator_age_ms <= 3600000
    error_message = "kinesis_iterator_age_ms must be between 0 and 3600000 (1 hour)."
  }

  validation {
    condition     = var.alarm_thresholds.kinesis_no_records_minutes >= 1 && var.alarm_thresholds.kinesis_no_records_minutes <= 60
    error_message = "kinesis_no_records_minutes must be between 1 and 60."
  }

  validation {
    condition     = var.alarm_thresholds.firehose_delivery_failure_percent >= 0 && var.alarm_thresholds.firehose_delivery_failure_percent <= 100
    error_message = "firehose_delivery_failure_percent must be between 0 and 100."
  }

  validation {
    condition     = var.alarm_thresholds.lambda_duration_p95_ms >= 0 && var.alarm_thresholds.lambda_duration_p95_ms <= 900000
    error_message = "lambda_duration_p95_ms must be between 0 and 900000 (15 minutes)."
  }
}

variable "flink_config" {
  description = "Configuração da aplicação Flink SQL (KDA V2)"
  type = object({
    parallelism = number
    auto_start  = bool
  })

  default = {
    parallelism = 1
    auto_start  = false
  }

  validation {
    condition     = var.flink_config.parallelism >= 1 && var.flink_config.parallelism <= 32
    error_message = "parallelism deve estar entre 1 e 32 KPUs."
  }
}

variable "redshift_config" {
  description = "Configuração do Redshift Serverless para data warehouse"
  type = object({
    admin_username        = string
    admin_password        = string
    base_capacity         = number
    max_capacity          = number
    backup_retention_days = number
    log_retention_days    = number
  })

  default = {
    admin_username        = "admin"
    admin_password        = "ChangeMe123!@#"
    base_capacity         = 32
    max_capacity          = 256
    backup_retention_days = 7
    log_retention_days    = 7
  }

  validation {
    condition     = length(var.redshift_config.admin_password) >= 8
    error_message = "admin_password deve ter no mínimo 8 caracteres."
  }

  validation {
    condition     = var.redshift_config.base_capacity >= 32
    error_message = "base_capacity deve ser no mínimo 32 RPUs."
  }

  validation {
    condition     = var.redshift_config.max_capacity >= var.redshift_config.base_capacity
    error_message = "max_capacity deve ser >= base_capacity."
  }
}

variable "sns_config" {
  description = "Configuração do SNS Topic para notificações de alertas"
  type = object({
    alert_email_addresses = list(string)
  })

  default = {
    alert_email_addresses = []
  }
}

# ============================================================================
# API Gateway + Lambda ingestion configuration
# ============================================================================

variable "create_api_gateway" {
  description = "Cria o API Gateway, o Usage Plan e a API Key. Use false em ambientes que não expõem borda (ex: dev local)."
  type        = bool
  default     = true
}

variable "create_api_key" {
  description = "Cria uma API Key vinculada ao Usage Plan. Quando false, chaves devem ser criadas externamente."
  type        = bool
  default     = true
}

variable "api_gateway_stage_name" {
  type    = string
  default = "v1"
}

variable "api_throttle_burst_limit" {
  description = "Burst máximo (token bucket) por API key no Usage Plan"
  type        = number
  default     = 200
}

variable "api_throttle_rate_limit" {
  description = "Taxa sustentada (req/s) por API key no Usage Plan"
  type        = number
  default     = 100
}

variable "api_quota_limit" {
  description = "Cota diária (requests) por API key no Usage Plan"
  type        = number
  default     = 100000
}

variable "lambda_flights_reserved_concurrency" {
  description = "Reserved concurrent executions for the ingestion Lambda. null = unreserved"
  type        = number
  default     = null
}

# ============================================================================
# RDS PostgreSQL configuration
# ============================================================================

variable "rds_snapshot_identifier" {
  description = "Override snapshot_identifier for RDS restore. Set via TF_VAR_rds_snapshot_identifier by restore-from-snapshot.sh."
  type        = string
  default     = null
}

variable "rds_admin_password" {
  description = "Override admin_password for RDS. Set via TF_VAR_rds_admin_password from .env file to avoid secrets in tfvars."
  type        = string
  sensitive   = true
  default     = null
}

# ============================================================================
# DMS configuration
# ============================================================================

variable "dms_config" {
  description = "Configuration for AWS DMS replication (RDS PostgreSQL -> S3 Parquet)"
  type = object({
    replication_instance_class = optional(string, "dms.t3.micro")
    replication_storage_gb     = optional(number, 50)
    engine_version             = optional(string, "3.5.3")
    enabled                    = optional(bool, false)
    table_mappings             = optional(string)
    dms_task_settings          = optional(string)
    full_load_instance_class   = optional(string)
  })
  default = {}
}

variable "rds_config" {
  description = "Configuration for the RDS PostgreSQL instance"
  type = object({
    vpc_id                  = string
    subnet_ids              = list(string)
    allowed_cidr_blocks     = list(string)
    db_name                 = optional(string, "flightradar")
    admin_username          = optional(string, "dbadmin")
    admin_password          = string
    instance_class          = optional(string, "db.t3.medium")
    allocated_storage_gb    = optional(number, 20)
    max_allocated_storage_gb = optional(number, 100)
    backup_retention_days   = optional(number, 7)
    publicly_accessible     = optional(bool, false)
    snapshot_identifier     = optional(string, null)
    read_replicas = optional(list(object({
      instance_class       = optional(string)
      allocated_storage_gb = optional(number)
      publicly_accessible  = optional(bool, false)
    })), [])
    skip_final_snapshot     = optional(bool, true)
    deletion_protection     = optional(bool, false)
    log_retention_days      = optional(number, 7)
  })
}
