variable "project_name" {
  description = "Nome do projeto para compor nomes dos recursos de monitoramento."
  type        = string
}

variable "alerts_topic_arn" {
  description = "ARN do tópico SNS para envio de alertas."
  type        = string
}

variable "flights_stream_name" {
  description = "Nome do stream Kinesis de flights."
  type        = string
}

variable "flights_lambda_function_name" {
  description = "Nome da função Lambda de processamento de flights."
  type        = string
}

variable "flights_table_name" {
  description = "Nome da tabela DynamoDB de flights."
  type        = string
}