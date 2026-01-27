variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "opensky_username" {
  description = "OpenSky API username"
  type        = string
  sensitive   = true
}

variable "opensky_password" {
  description = "OpenSky API password"
  type        = string
  sensitive   = true
}

variable "lambda_role_arns" {
  description = "List of Lambda IAM role ARNs that can access the secret"
  type        = list(string)
}

variable "recovery_window_days" {
  description = "Number of days for secret recovery window after deletion"
  type        = number
  default     = 7
}

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
