variable "project_name" {
  description = "Nome do projeto para compor nomes dos recursos Lambda"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "lambda_key" {
  description = "Chave da lambda no mapa de funções (ex: 'flights')"
  type        = string
}

variable "lambda_config" {
  description = "Configuração da função Lambda"
  type = object({
    name                              = string
    handler                          = string
    runtime                          = string
    timeout                          = number
    memory_size                      = number
    ephemeral_storage               = number
    schedule                         = string
    enabled                          = bool
    kinesis_stream                   = string
    requires_opensky_credentials    = bool
    reserved_concurrent_executions  = number
    tags                            = map(string)
  })
}

variable "kinesis_streams" {
  description = "Map of Kinesis stream names and their configurations"
  type = map(object({
    stream_name = string
    shard_count = number
  }))
}

variable "opensky_secret_arn" {
  description = "ARN of AWS Secrets Manager secret containing OpenSky API credentials"
  type        = string
}


variable "subnet_ids" {
  description = "IDs das subnets para VPC config"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "IDs dos security groups para VPC config"
  type        = list(string)
  default     = []
}

variable "enable_vpc" {
  description = "Habilitar VPC config para a Lambda"
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Número de dias para retenção dos logs"
  type        = number
  default     = 7
}

variable "enable_lambda_insights" {
  description = "Habilitar Lambda Insights para observabilidade"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags para todos os recursos"
  type        = map(string)
  default     = {}
}