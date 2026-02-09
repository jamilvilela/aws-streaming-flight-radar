output "nat_gateway_id" {
  value       = var.nat_gateway_enabled ? aws_nat_gateway.main[0].id : null
  description = "NAT Gateway ID"
}

output "nat_gateway_public_ip" {
  value       = var.nat_gateway_enabled ? aws_eip.nat[0].public_ip : null
  description = "NAT Gateway Elastic IP"
}

output "public_subnet_id" {
  value       = var.nat_gateway_enabled ? aws_subnet.public[0].id : null
  description = "Public subnet ID (for NAT Gateway)"
}

output "private_route_table_id" {
  value       = var.nat_gateway_enabled ? aws_route_table.private[0].id : null
  description = "Private route table ID"
}

output "internet_gateway_id" {
  value       = aws_internet_gateway.main.id
  description = "Internet Gateway ID"
}