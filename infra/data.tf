data "aws_caller_identity" "current" {} 

data "aws_s3_bucket" "landing" {
  bucket = local.buckets.landing
}

data "aws_iam_role" "datalake_role_name" {
  name = var.datalake_role_name
}