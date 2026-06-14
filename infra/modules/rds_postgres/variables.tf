variable "project_name" {
  description = "Project name used as resource prefix"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for RDS security group"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for RDS (minimum 2 in different AZs)"
  type        = list(string)
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to connect to PostgreSQL"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "flightradar"
}

variable "admin_username" {
  description = "Admin username for PostgreSQL"
  type        = string
  default     = "dbadmin"
}

variable "admin_password" {
  description = "Admin password for PostgreSQL"
  type        = string
  sensitive   = true
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.medium"
}

variable "allocated_storage_gb" {
  description = "Allocated storage in GB"
  type        = number
  default     = 20
}

variable "max_allocated_storage_gb" {
  description = "Maximum autoscaling storage in GB (0 to disable)"
  type        = number
  default     = 100
}

variable "backup_retention_days" {
  description = "Backup retention period in days"
  type        = number
  default     = 7
}

variable "backup_window" {
  description = "Daily backup window (UTC)"
  type        = string
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  description = "Weekly maintenance window (UTC)"
  type        = string
  default     = "sun:05:00-sun:06:00"
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when destroying (set false for prod)"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = false
}

variable "publicly_accessible" {
  description = "Make RDS publicly accessible"
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
}

variable "read_replicas" {
  description = "Read replica configurations. Each entry creates a read replica of the primary."
  type = list(object({
    instance_class       = optional(string)
    allocated_storage_gb = optional(number)
    publicly_accessible  = optional(bool, false)
  }))
  default = []
}

variable "snapshot_identifier" {
  description = "DB snapshot to restore from (null = create fresh). Set during restore workflow."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
