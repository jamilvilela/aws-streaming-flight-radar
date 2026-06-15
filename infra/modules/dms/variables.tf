variable "project_name" {
  description = "Project name used as resource prefix"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "region" {
  description = "AWS Region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for DMS security group"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for DMS replication instance (minimum 2)"
  type        = list(string)
}

variable "rds_endpoint" {
  description = "RDS PostgreSQL endpoint address"
  type        = string
}

variable "rds_port" {
  description = "RDS PostgreSQL port"
  type        = number
  default     = 5432
}

variable "rds_db_name" {
  description = "RDS PostgreSQL database name"
  type        = string
}

variable "rds_security_group_id" {
  description = "RDS security group ID (DMS needs ingress)"
  type        = string
}

variable "landing_bucket_name" {
  description = "S3 landing bucket name for DMS target output"
  type        = string
}

variable "replication_instance_class" {
  description = "DMS replication instance class"
  type        = string
  default     = "dms.t3.micro"
}

variable "replication_storage_gb" {
  description = "Allocated storage for DMS replication instance in GB"
  type        = number
  default     = 50
}

variable "replication_engine_version" {
  description = "DMS replication engine version"
  type        = string
  default     = "3.5.3"
}

variable "dms_task_settings" {
  description = "DMS task settings JSON (full load + CDC)"
  type        = string
  default     = null
}

variable "table_mappings" {
  description = "DMS table mappings JSON (selection rules, transformations)"
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
