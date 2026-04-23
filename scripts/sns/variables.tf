# ============================================================================
# SNS Module - Input Variables
# ============================================================================

variable "project_name" {
  description = "Project name for SNS topic naming"
  type        = string
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
}

variable "alert_email_addresses" {
  description = "List of email addresses to subscribe to KDA alerts"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for email in var.alert_email_addresses : 
      can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All email addresses must be valid format."
  }
}

variable "sqs_queue_arn" {
  description = "ARN of SQS queue to subscribe to SNS (for async processing)"
  type        = string
  default     = ""
}

variable "lambda_function_arn" {
  description = "ARN of Lambda function to subscribe to SNS (for custom processing)"
  type        = string
  default     = ""
}

variable "allow_kda_publish" {
  description = "Allow KDA service principal to publish to SNS topic"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for SNS topic encryption (optional)"
  type        = string
  default     = ""
}

variable "enable_delivery_status_logging" {
  description = "Enable SNS delivery status logging to CloudWatch"
  type        = bool
  default     = false
}

variable "create_publish_failure_alarm" {
  description = "Create CloudWatch alarm for SNS publish failures"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
