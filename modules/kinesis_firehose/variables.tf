variable "name" {
  description = "Firehose delivery stream name"
  type        = string
}

variable "kinesis_stream_arn" {
  description = "ARN of the Kinesis Data Stream"
  type        = string
}

variable "firehose_role_arn" {
  description = "IAM Role ARN for Firehose"
  type        = string
}

variable "buckets" {
  description = "S3 buckets for the data lake"
  type = object({
    workspace = string
    landing   = string
    raw       = string
  })
}


variable "prefix" {
  description = "S3 prefix for delivered data"
  type        = string
  default     = "raw/"
}

variable "tags" {
  description = "Tags for the Firehose stream"
  type        = map(string)
  default     = {}
}