variable "lambda_arns" {
  description = "A map of Lambda function ARNs to associate with EventBridge rules."
  type        = map(string)
}

variable "schedule" {
  description = "The schedule expression for the EventBridge rule (e.g., cron or rate expression)."
  type        = string
}