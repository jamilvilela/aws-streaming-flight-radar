variable "project_name" {
  type = string
}

variable "api_name" {
  type    = string
  default = "flights-ingest"
}

variable "api_description" {
  type    = string
  default = "Edge API for ingesting flight data into the streaming pipeline"
}

variable "endpoint_type" {
  type    = string
  default = "REGIONAL"
  validation {
    condition     = contains(["REGIONAL", "EDGE"], var.endpoint_type)
    error_message = "endpoint_type must be REGIONAL or EDGE."
  }
}

variable "stage_name" {
  type    = string
  default = "v1"
}

variable "lambda_invoke_arn" {
  type        = string
  description = "Invoke ARN of the ingestion Lambda"
}

variable "authorizer_invoke_arn" {
  type        = string
  description = "Invoke ARN of the Lambda authorizer (used by the API Gateway authorizer integration URI)"
}

variable "authorizer_function_arn" {
  type        = string
  description = "Plain ARN of the Lambda authorizer function (used by IAM policies; the invoke ARN is not a valid IAM resource)"
}

variable "throttle_burst_limit" {
  type    = number
  default = 200
}

variable "throttle_rate_limit" {
  type    = number
  default = 100
}

variable "quota_limit" {
  type        = number
  default     = 100000
  description = "Daily request quota per API key"
}

variable "quota_period" {
  type    = string
  default = "DAY"
}

variable "create_api_key" {
  type    = bool
  default = true
}

variable "create_api_gateway" {
  type        = bool
  default     = true
  description = "When false, the module is a no-op (no API, no IAM, no logs)"
}

variable "enable_access_logs" {
  type    = bool
  default = true
}

variable "access_log_retention_days" {
  type    = number
  default = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}
