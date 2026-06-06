variable "lambda_config" {
  type = object({
    name              = string
    handler           = string
    runtime           = string
    timeout           = number
    memory_size       = number
    ephemeral_storage = number
  })
}

variable "project_name" { type = string }
variable "aws_region" { type = string }

variable "environment_variables" {
  type    = map(string)
  default = {}
}

variable "log_retention_days" {
  type    = number
  default = 7
}

variable "tags" {
  type    = map(string)
  default = {}
}
