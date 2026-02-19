variable "project_name" { type = string }
variable "aws_region"   { type = string }
variable "environment"  { type = string }
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
