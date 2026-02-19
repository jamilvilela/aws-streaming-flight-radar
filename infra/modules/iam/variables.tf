variable "project_name" {
  type        = string
  description = "Nome do projeto para prefixar recursos"
}

variable "tags" {
  type        = map(string)
  description = "Tags comuns para todos os recursos"
}

variable "kinesis_arns" {
  type        = list(string)
  description = "Lista de ARNs dos Kinesis Streams que a Lambda/Firehose acessam"
}

variable "bucket_arn" {
  type        = string
  description = "ARN do bucket S3 destino do Firehose"
}

variable "lambda_arn" {
  type        = string
  description = "ARN da Lambda usada como transform processor no Firehose"
}
