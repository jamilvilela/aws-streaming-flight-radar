output "kinesis_stream_flights_info" {
  value = module.kinesis_stream_flights.kinesis_streams_info
}

output "lambda_flights_function_arn" {
  value = module.lambda_flights.function_arn
}

output "lambda_flights_function_name" {
  value = module.lambda_flights.function_name
}

output "lambda_flights_iam_role_arn" {
  value = module.lambda_flights.iam_role_arn
}

output "flights_dlq_url" {
  value = module.flights_dlq.queue_url
}

output "flights_dlq_arn" {
  value = module.flights_dlq.queue_arn
}

output "api_invoke_url" {
  description = "Base invoke URL of the edge API (e.g. https://<id>.execute-api.us-east-1.amazonaws.com/v1)"
  value       = module.api_gateway.stage_invoke_url
}

output "api_id" {
  value = module.api_gateway.api_id
}

output "api_key_id" {
  value = module.api_gateway.api_key_id
}

output "api_key_value" {
  value     = module.api_gateway.api_key_value
  sensitive = true
}
