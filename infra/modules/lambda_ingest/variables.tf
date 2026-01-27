variable "datalake_role_name" {
  type = string  
}

variable "project_name" {
  description = "Nome do projeto para compor nomes dos recursos Lambda."
  type        = string
}

variable "kinesis_streams" {
  description = "Map of Kinesis stream names and their configurations"
  type = map(object({
    shard_count = number
  }))
  default = {}
}

variable "timeout" {
  description = "Timeout (em segundos) para as funções Lambda."
  type        = number
  default     = 60
}