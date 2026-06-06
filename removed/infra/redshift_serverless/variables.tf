# ============================================================================
# Input Variables for Redshift Serverless Module
# ============================================================================

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "region" {
  description = "AWS region for Redshift"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for Redshift"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for Redshift (minimum 2 in different AZs)"
  type        = list(string)
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to connect to Redshift"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "database_name" {
  description = "Initial database name"
  type        = string
  default     = "flightradar"
}

variable "admin_username" {
  description = "Admin username for Redshift"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "admin_password" {
  description = "Admin password for Redshift (min 8 chars, must include uppercase, lowercase, digit, special char)"
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.admin_password) >= 8 && can(regex("[A-Z]", var.admin_password)) && can(regex("[a-z]", var.admin_password)) && can(regex("[0-9]", var.admin_password)) && can(regex("[!@#$%^&*()_+\\-=\\[\\]{};':\"\\\\|,.<>?]", var.admin_password))
    error_message = "Password must be at least 8 characters and contain uppercase, lowercase, digit, and special character."
  }
}

variable "base_capacity" {
  description = "Base capacity in RPUs (Redshift Processing Units)"
  type        = number
  default     = 32  # Minimum is 32
}

variable "max_capacity" {
  description = "Maximum auto-scaling capacity in RPUs"
  type        = number
  default     = 512
}

variable "publicly_accessible" {
  description = "Make Redshift publicly accessible"
  type        = bool
  default     = false
}

variable "enhanced_vpc_routing" {
  description = "Enable enhanced VPC routing"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Backup retention period in days"
  type        = number
  default     = 7
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
}

variable "create_parameter_group" {
  description = "Create a parameter group for the workgroup"
  type        = bool
  default     = false
}

variable "kda_flights_stream_arns" {
  description = "ARNs of Kinesis streams from KDA for data loading"
  type        = list(string)
  default     = []
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for KDA alerts (to subscribe Redshift)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
