variable "lambda_config" {
  description = "Lambda function runtime configuration"
  type = object({
    name              = string
    handler           = string
    runtime           = string
    timeout           = number
    memory_size       = number
    ephemeral_storage = number
  })
}

variable "project_name" {
  type        = string
  description = "Project name used as resource prefix"
}

variable "aws_region" {
  type        = string
  description = "AWS region (used for log group ARNs)"
}

variable "kinesis_stream_name" {
  type        = string
  description = "Name of the Kinesis Data Stream that the Lambda writes to"
}

variable "kinesis_stream_arn" {
  type        = string
  description = "ARN of the Kinesis Data Stream that the Lambda writes to (used for IAM scoping)"
}

variable "dlq_queue_arn" {
  type        = string
  description = "ARN of the SQS DLQ used for invalid records"
}

variable "dlq_queue_url" {
  type        = string
  description = "URL of the SQS DLQ (passed to the Lambda as DLQ_URL for the producer)"
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "reserved_concurrent_executions" {
  description = "Reserved concurrent executions for the Lambda (null = unreserved)"
  type        = number
  default     = null
}

variable "log_retention_days" {
  description = "CloudWatch log group retention in days"
  type        = number
  default     = 7
}

variable "api_gateway_execution_arn" {
  description = "API Gateway execute-api ARN pattern granting apigateway.amazonaws.com permission to invoke this Lambda. Empty string disables the permission."
  type        = string
  default     = ""
}

variable "layer_arns" {
  description = "List of Lambda Layer ARNs to attach (e.g. shared Python layer with pydantic)"
  type        = list(string)
  default     = []
}
