output "lambda_flights_raw_arn" {
  value = module.lambda_flights_raw.lambda_arn
}

output "lambda_flights_raw_iam_role_arn" {
  value = module.lambda_flights_raw.iam_role_arn
}

output "kinesis_analytics_flights_iam_role_arn" {
  value = module.kinesis_analytics_flights.iam_role_arn
}

# output "lambda_flights_enriched_arn" {
#   value       = module.lambda_flights_enriched.lambda_arn
# }
output "kinesis_stream_flights_info" {
  value = module.kinesis_stream_flights.kinesis_streams_info
}
# output "kinesis_firehose_to_opensearch_info" {
#   value       = module.kinesis_firehose_flights.kinesis_firehose_to_opensearch_info
# }
# output "opensearch_collection_endpoint" {
#   value = module.opensearch.collection_endpoint
# }
# output "opensearch_dashboard_endpoint" {
#   value = module.opensearch.dashboard_endpoint
# }