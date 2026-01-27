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

############################################
# Glue Catalog variables
variable "databases" {
  description = "Glue databases for the data lake"
  type = object({
    raw      = string
  })
}

variable "tables" {
  description = "Glue tables for the data lake"
  type = object({
    etl_control  = string
    data_quality = string
  })
}

##############################################
# User credentials for the data lake
variable "users" {
  description = "User credentials for the data lake"
  type = object({
    datalake_user1     = object({
      name     = string
    })
  })
}

##############################################
# Flight Radar data stream variables
variable "tags" {
  description = "Tags for the Flight Radar data stream and related resources"
  type        = map(string)
  default     = {}
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "project_name" {
  description = "Nome do projeto"
  type        = string
}

###############################################
# Kinesis Data Streams variables
variable "kinesis_streams" {
  description = "Map of Kinesis stream names and their configurations"
  type = map(object({
    shard_count = number
  }))
  default = {}
}

variable "ingestion_schedule" {
  description = "Schedule do EventBridge"
  type        = string
}

variable "lambda_ingest_timeout" {
  description = "Timeout das funções de ingestão"
  type        = number
}

variable "lambda_processor_timeout" {
  description = "Timeout das funções de processamento"
  type        = number
}