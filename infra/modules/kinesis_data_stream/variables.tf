variable "project_name" {
  description = "Nome do projeto para compor nomes dos streams."
  type        = string
}

variable "tags" {
  description = "Tags a serem aplicadas aos recursos Kinesis."
  type        = map(string)
  default     = {}
}

variable "kinesis_streams" {
  description = "Map of Kinesis stream names and their configurations"
  type = map(object({
    shard_count = number
  }))
  default = {}
}