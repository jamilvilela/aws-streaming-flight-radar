variable "control_account" {
  type = string
}

############################################
# IAM variables
variable "datalake_role_name" {
  type = string  
}

############################################
# S3 bucket variables
variable "buckets" {
  description = "S3 buckets for the data lake"
  type = object({
    workspace = string
    landing   = string
    raw       = string
  })
}


##############################################
# Flight Radar data stream variables
variable "tags" {
  description = "Tags for the Flight Radar data stream and related resources"
  type        = map(string)
  default     = {}
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "project_name" {
  description = "Nome do projeto"
  type        = string
}

variable "environment" {
  description = "Ambiente (production, staging, development)"
  type        = string
  default     = "production"
  validation {
    condition     = contains(["production", "staging", "development"], var.environment)
    error_message = "Environment deve ser production, staging ou development."
  }
}

###############################################
# Kinesis Data Streams variables
variable "kinesis_streams" {
  description = "Map of Kinesis stream names and their configurations"
  type = map(object({
    stream_name = string
    shard_count = number
  }))
  default = {}
}

###############################################
# Lambda Functions Configuration
variable "lambda_functions" {
  description = "Map of Lambda functions with their configurations"
  type = map(object({
    name                              = string
    handler                          = string
    runtime                          = string
    timeout                          = number
    memory_size                      = number
    ephemeral_storage               = number
    schedule                         = string      # EventBridge schedule expression
    enabled                          = bool
    kinesis_stream                   = string
    requires_opensky_credentials    = bool
    reserved_concurrent_executions  = number
    tags                            = map(string)
  }))
  validation {
    condition = alltrue([
      for func in var.lambda_functions :
      func.timeout > 0 && func.timeout <= 900
    ])
    error_message = "Lambda timeout deve ser entre 1 e 900 segundos."
  }
}

variable "opensky_client_id" {
  description = "OpenSky API client_id (will be stored in AWS Secrets Manager)"
  type        = string
  sensitive   = true
}

variable "opensky_client_secret" {
  description = "OpenSky API client_secret (will be stored in AWS Secrets Manager)"
  type        = string
  sensitive   = true
}

###############################################
# AWS Secrets Manager Configuration
variable "secrets_recovery_window_days" {
  description = "Number of days before a deleted secret is permanently deleted"
  type        = number
  default     = 7
}

variable "secrets_log_retention_days" {
  description = "CloudWatch logs retention period for Secrets Manager audit logs"
  type        = number
  default     = 7
}

###############################################
# VPC Configuration 
variable "enable_vpc" {
  description = "Habilitar VPC config para a Lambda"
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC ID where Lambda functions will be deployed"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "IDs das subnets para VPC config"
  type        = list(string)
  default     = []
}

variable "nat_gateway_enabled" {
  type        = bool
  default     = false
  description = "Enable NAT Gateway for Lambda in VPC"
}

