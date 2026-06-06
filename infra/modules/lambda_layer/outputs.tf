output "arn" {
  description = "Full ARN of the published layer version. Pass to lambda.layers in any Lambda module."
  value       = aws_lambda_layer_version.this.arn
}

output "layer_name" {
  description = "Name of the layer (without version suffix)."
  value       = aws_lambda_layer_version.this.layer_name
}

output "version" {
  description = "Numeric version of the published layer (increments on every change to the source content)."
  value       = aws_lambda_layer_version.this.version
}

output "source_code_hash" {
  description = "Base64 sha256 of the zip. Useful as a trigger or for wiring into other resources."
  value       = aws_lambda_layer_version.this.source_code_hash
}
