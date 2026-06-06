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
  description = "Invoke ARN of the Lambda authorizer"
}

variable "authorizer_credentials_arn" {
  type        = string
  description = "IAM role ARN that API Gateway assumes to invoke the authorizer"
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
  type    = number
  default = 100000
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

variable "enable_access_logs" {
  type    = bool
  default = true
}

variable "access_log_group_arn" {
  type        = string
  default     = null
  description = "CloudWatch log group ARN for access logs (required if enable_access_logs = true)"
}

variable "tags" {
  type    = map(string)
  default = {}
}
