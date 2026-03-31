variable "project_name" { type = string }
variable "aws_region"   { type = string }
variable "environment"  { type = string }

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

variable "tags"         { 
  type = map(string) 
  default = {} 
}

variable "kinesis_streams" {
  description = "Map of Kinesis stream names and their configurations"
  type = map(object({
    name = string
    mode = string  # "ON_DEMAND" ou "PROVISIONED"
  }))
}


variable "kinesis_firehose" {
  description = "Configuração de um único firehose Kinesis"
  type = map(object({
    name              = string
    prefix             = string
    error_output_prefix = string
    opensearch_index_name = string
  }))
}

variable "lambda_functions" {
  description = "Map of Lambda function configurations"
  type        = map(object({
    name                          = string
    handler                       = string
    runtime                       = string
    timeout                       = number
    memory_size                   = number
    ephemeral_storage             = number
    tags                          = map(string)
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

variable "opensearch" {
  description = "Configurações do OpenSearch Serverless"
  type = object({
    flights = object({
      collection_name    = string
      collection_type    = string
      standby_replicas   = string
      vpc_id             = string
    })
  })
  default = {
    flights = {
      collection_name    = "flight-radar-flights"
      collection_type    = "SEARCH"
      standby_replicas   = "ENABLED"
      vpc_id             = ""
    }
  }
  validation {
    condition = contains(
      ["SEARCH", "TIMESERIES", "VECTORSEARCH"],
      var.opensearch.flights.collection_type
    )
    error_message = "collection_type must be one of: SEARCH, TIMESERIES, VECTORSEARCH."
  }
  validation {
    condition = contains(
      ["ENABLED", "DISABLED"],
      var.opensearch.flights.standby_replicas
    )
    error_message = "standby_replicas must be either ENABLED or DISABLED."
  }
  validation {
    condition = length(var.opensearch.flights.collection_name) >= 3 && length(var.opensearch.flights.collection_name) <= 63 && can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.opensearch.flights.collection_name))
    error_message = "collection_name must be 3-63 characters, start with letter, end with letter/number, lowercase only."
  }
}

variable "alarm_thresholds" {
  description = "Thresholds personalizáveis para alarmes CloudWatch"
  type = object({
    # Kinesis Stream
    kinesis_iterator_age_ms           = number
    kinesis_no_records_minutes        = number
    kinesis_write_throttle_percent    = number
    kinesis_read_throttle_percent     = number
    
    # Kinesis Firehose
    firehose_delivery_failure_percent = number
    firehose_incoming_records_low     = number
    
    # Lambda Functions
    lambda_error_percent              = number
    lambda_duration_p95_ms            = number
    lambda_throttle_count             = number
    
    # OpenSearch Cluster (Legacy)
    opensearch_cpu_percent            = optional(number, 80)
    opensearch_jvm_memory_percent     = optional(number, 85)
    
    # OpenSearch Serverless (Novo)
    opensearch_ocu_utilization        = optional(number, 80)
    
    # OpenSearch (Ambos)
    opensearch_indexing_failures      = number
  })
  
  default = {
    # Kinesis Stream
    kinesis_iterator_age_ms           = 60000    # 60 segundos
    kinesis_no_records_minutes        = 10       # 10 minutos
    kinesis_write_throttle_percent    = 5        # 5%
    kinesis_read_throttle_percent     = 5        # 5%
    
    # Kinesis Firehose
    firehose_delivery_failure_percent = 10       # 10%
    firehose_incoming_records_low     = 1        # 1 registro
    
    # Lambda Functions
    lambda_error_percent              = 5        # 5%
    lambda_duration_p95_ms            = 5000     # 5 segundos
    lambda_throttle_count             = 10       # 10 throttles
    
    # OpenSearch Cluster (Legacy)
    opensearch_cpu_percent            = 80       # 80%
    opensearch_jvm_memory_percent     = 85       # 85%
    
    # OpenSearch Serverless (Novo)
    opensearch_ocu_utilization        = 80       # 80%
    
    # OpenSearch (Ambos)
    opensearch_indexing_failures      = 5        # 5 falhas
  }

  validation {
    condition = var.alarm_thresholds.kinesis_iterator_age_ms >= 0 && var.alarm_thresholds.kinesis_iterator_age_ms <= 3600000
    error_message = "kinesis_iterator_age_ms must be between 0 and 3600000 (1 hour)."
  }

  validation {
    condition = var.alarm_thresholds.kinesis_no_records_minutes >= 1 && var.alarm_thresholds.kinesis_no_records_minutes <= 60
    error_message = "kinesis_no_records_minutes must be between 1 and 60."
  }

  validation {
    condition = var.alarm_thresholds.firehose_delivery_failure_percent >= 0 && var.alarm_thresholds.firehose_delivery_failure_percent <= 100
    error_message = "firehose_delivery_failure_percent must be between 0 and 100."
  }

  validation {
    condition = var.alarm_thresholds.lambda_duration_p95_ms >= 0 && var.alarm_thresholds.lambda_duration_p95_ms <= 900000
    error_message = "lambda_duration_p95_ms must be between 0 and 900000 (15 minutes)."
  }

  validation {
    condition = var.alarm_thresholds.opensearch_cpu_percent >= 0 && var.alarm_thresholds.opensearch_cpu_percent <= 100
    error_message = "opensearch_cpu_percent must be between 0 and 100."
  }

  validation {
    condition = var.alarm_thresholds.opensearch_jvm_memory_percent >= 0 && var.alarm_thresholds.opensearch_jvm_memory_percent <= 100
    error_message = "opensearch_jvm_memory_percent must be between 0 and 100."
  }

  validation {
    condition = var.alarm_thresholds.opensearch_ocu_utilization >= 0 && var.alarm_thresholds.opensearch_ocu_utilization <= 100
    error_message = "opensearch_ocu_utilization must be between 0 and 100."
  }
}