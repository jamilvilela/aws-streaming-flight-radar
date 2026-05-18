output "collection_id" {
  description = "ID da collection OpenSearch Serverless"
  value       = aws_opensearchserverless_collection.flights.id
}

output "collection_arn" {
  description = "ARN da collection"
  value       = aws_opensearchserverless_collection.flights.arn
}

output "collection_endpoint" {
  description = "Endpoint da collection para conexões"
  value       = aws_opensearchserverless_collection.flights.collection_endpoint
}

output "dashboard_endpoint" {
  description = "Endpoint do OpenSearch Dashboards"
  value       = aws_opensearchserverless_collection.flights.dashboard_endpoint
}

output "encryption_policy_id" {
  description = "ID da política de encryption"
  value       = aws_opensearchserverless_security_policy.encryption.id
}

output "network_policy_id" {
  description = "ID da política de network"
  value       = aws_opensearchserverless_security_policy.network.id
}

output "access_policy_id" {
  description = "ID da política de acesso"
  value       = aws_opensearchserverless_access_policy.flights_access.id
}

output "lifecycle_policy_id" {
  description = "ID da política de lifecycle"
  value       = try(aws_opensearchserverless_lifecycle_policy.flights.id, null)
}