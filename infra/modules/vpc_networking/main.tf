# ===== ELASTIC IP PARA NAT GATEWAY =====
resource "aws_eip" "nat" {
  count  = var.nat_gateway_enabled ? 1 : 0
  domain = "vpc"

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-eip-nat"
    }
  )
}

# ===== NAT GATEWAY =====
resource "aws_nat_gateway" "main" {
  count         = var.nat_gateway_enabled ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = var.subnet_ids[0]

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-nat-gateway"
    }
  )
}

resource "aws_route_table" "private" {
  count  = var.nat_gateway_enabled ? 1 : 0
  vpc_id = var.vpc_id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[0].id
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-rt-private"
      Type = "private"
    }
  )
}

resource "aws_route_table_association" "private" {
  count          = var.nat_gateway_enabled ? length(var.subnet_ids) : 0
  subnet_id      = var.subnet_ids[count.index]
  route_table_id = aws_route_table.private[0].id
}