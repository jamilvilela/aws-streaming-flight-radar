variable "project_name" {
  description = "Nome do projeto"
  type        = string
}

variable "environment" {
  description = "Environment (production, staging, development)"
  type        = string
  default     = "production"
}

variable "bucket_arn" {
  description = "ARN do bucket S3 para armazenamento dos dados enriquecidos"
  type        = string
}


variable "tags" {
  description = "Tags a serem aplicadas aos recursos Kinesis"
  type        = map(string)
  default     = {}
}

variable "kinesis_firehose" {
  description = "Configuração do firehose Kinesis flights enriched"
  type = object({
    name                = string
    prefix              = string
    error_output_prefix = string
  })
}

variable "role_arn" {
  description = "ARN da role IAM para o Kinesis Firehose"
  type        = string
}

# variable "lambda_arn" {
#   description = "ARN da função Lambda para processamento dos dados no Kinesis Firehose"
#   type        = string
# }

variable "kinesis_stream_arn" {
  description = "ARN do Kinesis Stream data source"
  type = string
}

# variable "databases" {
#   type        = map(string)
#   description = "Mapa com os nomes dos Glue Databases já existentes no Glue Data Catalog"
# }

# variable "tables" {
#   type        = map(string)
#   description = "Mapa com os nomes das tabelas Glue a serem criadas para armazenar o schema dos dados"
# }

variable "kms_firehose_arn" {
  description = "ARN da chave KMS para criptografia do Kinesis Firehose"
  type        = string
}

# variable "opensearch_collection_arn" {
#   description = "ARN da collection OpenSearch para onde o Firehose irá enviar os dados"
#   type        = string  
# }

variable "opensearch_collection_endpoint" {
  description = "Endpoint da collection OpenSearch para onde o Firehose irá enviar os dados"
  type = string
}

variable "opensearch_index_name" {
  description = "Nome do index no OpenSearch onde os dados serão armazenados"
  type        = string
}