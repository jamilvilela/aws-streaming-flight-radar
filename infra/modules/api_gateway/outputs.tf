output "api_id" {
  value = aws_api_gateway_rest_api.this.id
}

output "api_arn" {
  value = aws_api_gateway_rest_api.this.arn
}

output "stage_invoke_url" {
  value = aws_api_gateway_stage.this.invoke_url
}

output "stage_name" {
  value = aws_api_gateway_stage.this.stage_name
}

output "usage_plan_id" {
  value = aws_api_gateway_usage_plan.this.id
}

output "api_key_id" {
  value = var.create_api_key ? aws_api_gateway_api_key.this[0].id : ""
}

output "api_key_value" {
  value     = var.create_api_key ? aws_api_gateway_api_key.this[0].value : ""
  sensitive = true
}
