variable "lambda_key" {
  description = "Chave da Lambda no mapa de funções"
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

variable "lambda_arn" {
  description = "ARN da função Lambda a ser disparada"
  type        = string
}

variable "lambda_name" {
  description = "Nome da função Lambda a ser disparada"
  type        = string
}