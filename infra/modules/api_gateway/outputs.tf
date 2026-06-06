output "api_id" {
  value = var.create_api_gateway ? aws_api_gateway_rest_api.this[0].id : ""
}

output "api_arn" {
  value = var.create_api_gateway ? aws_api_gateway_rest_api.this[0].arn : ""
}

output "execution_arn" {
  description = "API Gateway execute-api ARN pattern (*/*) used by resource-based Lambda permissions."
  value       = var.create_api_gateway ? "${aws_api_gateway_rest_api.this[0].execution_arn}/*/*" : ""
}

output "stage_invoke_url" {
  value = var.create_api_gateway ? aws_api_gateway_stage.this[0].invoke_url : ""
}

output "stage_name" {
  value = var.stage_name
}

output "usage_plan_id" {
  value = var.create_api_gateway ? aws_api_gateway_usage_plan.this[0].id : ""
}

output "api_key_id" {
  value = (var.create_api_gateway && var.create_api_key) ? aws_api_gateway_api_key.this[0].id : ""
}

output "api_key_value" {
  value     = (var.create_api_gateway && var.create_api_key) ? aws_api_gateway_api_key.this[0].value : ""
  sensitive = true
}
