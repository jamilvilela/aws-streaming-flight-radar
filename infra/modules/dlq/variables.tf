variable "project_name" {
  type        = string
  description = "Project name used as queue prefix"
}

variable "name" {
  type        = string
  description = "Logical name suffix (e.g. 'flights-dlq')"
}

variable "visibility_timeout_seconds" {
  type        = number
  default     = 300
  description = "How long messages stay invisible after being read"
}

variable "message_retention_seconds" {
  type        = number
  default     = 1209600 # 14 days
  description = "How long messages are retained if not consumed"
}

variable "kms_key_id" {
  type        = string
  default     = null
  description = "KMS key for SQS at-rest encryption (uses AWS managed key if null)"
}

variable "redrive_policy" {
  type = object({
    dead_letter_target_arn = string
    max_receive_count      = number
  })
  default     = null
  description = "Optional redrive (e.g. forward to a longer retention queue)"
}

variable "attach_queue_policy" {
  type        = bool
  default     = false
  description = "If true, attach an inline SQS resource policy allowing the producer role to send messages"
}

variable "producer_role_arn" {
  type        = string
  default     = ""
  description = "ARN of the IAM role allowed to send messages to the queue (used when attach_queue_policy = true)"
}

variable "tags" {
  type    = map(string)
  default = {}
}
