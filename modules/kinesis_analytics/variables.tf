variable "project_name" {
  description = "Nome do projeto para compor nomes de recursos."
  type        = string
}

variable "code_bucket_name" {
  description = "Nome do bucket S3 onde o código do Flink está armazenado."
  type        = string
}

variable "flink_app_jar_key" {
  description = "Chave do arquivo JAR do aplicativo Flink no bucket S3."
  type        = string
}

variable "analytics_role_arn" {
  description = "ARN do papel de execução para a aplicação Kinesis Analytics."
  type        = string
}