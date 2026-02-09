variable "aws_region" {
  type        = string
  description = "AWS region"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID to configure"
}

variable "vpc_cidr" {
  type        = string
  default     = "172.31.0.0/16"
  description = "VPC CIDR block (default VPC)"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for Lambda"
}

variable "availability_zone" {
  type        = string
  default     = "us-east-1a"
  description = "Availability zone for public subnet"
}

variable "public_subnet_cidr" {
  type        = string
  default     = "172.31.0.0/20"
  description = "CIDR block for public subnet"
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