output "lambda_flights_raw_arn" {
  value       = module.lambda_flights_raw.lambda_arn
}
output "lambda_flights_enriched_arn" {
  value       = module.lambda_flights_enriched.lambda_arn
}
output "kinesis_stream_flights_raw_info" {
  value = module.kinesis_stream_flights_raw.kinesis_streams_info
}
output "kinesis_firehose_flights_enriched_info" {
  value       = module.kinesis_firehose_flights_enriched.kinesis_firehose_flights_enriched_info
}
output "iam_lambda_execution_role_arn" {
  value       = module.iam.lambda_execution_role_arn
}
