variable "project_name" {
  description = "Nome do projeto"
  type        = string
}

variable "environment" {
  description = "Environment (production, staging, development)"
  type        = string
  default     = "production"
}

variable "retention_hours" {
  description = "Período de retenção dos dados em horas (24-8760)"
  type        = number
  default     = 24
  validation {
    condition     = var.retention_hours >= 24 && var.retention_hours <= 8760
    error_message = "Retention deve estar entre 24 e 8760 horas."
  }
}

variable "tags" {
  description = "Tags a serem aplicadas aos recursos Kinesis"
  type        = map(string)
  default     = {}
}

variable "kinesis_streams" {
  description = "Mapa de streams Kinesis e suas configurações"
  type = map(object({
    stream_name = string
    shard_count = number  # Ignorado em modo ON_DEMAND, mas mantido para compatibilidade
  }))
  default = {}
}