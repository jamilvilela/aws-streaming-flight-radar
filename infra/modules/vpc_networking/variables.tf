variable "vpc_id" {
  type        = string
  description = "VPC ID to configure"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for Lambda"
}

variable "nat_gateway_enabled" {
  type        = bool
  default     = false
  description = "Enable NAT Gateway for private Lambda"
}

variable "project_name" {
  type        = string
  description = "Project name"
}

variable "tags" {
  type        = map(string)
  description = "Common tags"
  default     = {}
}
