output "queue_arn" {
  description = "ARN of the SQS queue"
  value       = aws_sqs_queue.dlq.arn
}

output "queue_id" {
  description = "ID of the SQS queue"
  value       = aws_sqs_queue.dlq.id
}

output "queue_url" {
  description = "URL of the SQS queue (used by producers/consumers)"
  value       = aws_sqs_queue.dlq.url
}

output "queue_name" {
  description = "Name of the SQS queue"
  value       = aws_sqs_queue.dlq.name
}
