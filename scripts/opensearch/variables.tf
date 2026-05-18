variable "project_name" {
  description = "Nome do projeto"
  type        = string
}

variable "environment" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
}

variable "collection_name" {
  description = "Nome da collection OpenSearch Serverless"
  type        = string
}

variable "collection_type" {
  description = "Tipo da collection: SEARCH, TIMESERIES, ou VECTORSEARCH"
  type        = string
  default     = "SEARCH"
  validation {
    condition     = contains(["SEARCH", "TIMESERIES", "VECTORSEARCH"], var.collection_type)
    error_message = "Collection type must be SEARCH, TIMESERIES, or VECTORSEARCH."
  }
}

variable "firehose_role_arn" {
  description = "ARN da role do Firehose para acesso à collection"
  type        = string
}

variable "dash_user_arns" {
  description = "Lista de ARNs de usuários para acesso ao OpenSearch Dashboards"
  type        = list(string)
  default     = []
}

variable "vpc_id" {
  description = "VPC ID para network policy (opcional, deixa público se vazio)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags para recursos"
  type        = map(string)
  default     = {}
}

variable "standby_replicas" {
  description = "Réplicas standby para alta disponibilidade (ENABLED/DISABLED)"
  type        = string
  default     = "DISABLED"
}