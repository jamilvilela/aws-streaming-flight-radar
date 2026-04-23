data "aws_caller_identity" "current" {} 

data "aws_s3_bucket" "landing" {
  bucket = local.buckets.landing
}

data "aws_iam_role" "datalake_role_name" {
  name = var.datalake_role_name
}

# ============================================================================
# VPC and Network Data Sources (for Redshift)
# ============================================================================

data "aws_vpc" "main" {
  default = true
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  
  filter {
    name   = "tag:Name"
    values = ["*private*"]
  }
}