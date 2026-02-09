# ===== INTERNET GATEWAY =====
resource "aws_internet_gateway" "main" {
  vpc_id = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-igw"
    }
  )
}

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

  depends_on = [aws_internet_gateway.main]
}

# ===== SUBNET PÚBLICA (para NAT Gateway) =====
resource "aws_subnet" "public" {
  count                   = var.nat_gateway_enabled ? 1 : 0
  vpc_id                  = var.vpc_id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-subnet-public"
      Type = "public"
    }
  )
}

# ===== NAT GATEWAY =====
resource "aws_nat_gateway" "main" {
  count         = var.nat_gateway_enabled ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-nat-gateway"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

# ===== ROUTE TABLE PÚBLICA (para subnet pública) =====
resource "aws_route_table" "public" {
  count  = var.nat_gateway_enabled ? 1 : 0
  vpc_id = var.vpc_id

  route {
    cidr_block      = "0.0.0.0/0"
    gateway_id      = aws_internet_gateway.main.id
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-rt-public"
      Type = "public"
    }
  )
}

# ===== ASSOCIAÇÃO: SUBNET PÚBLICA COM ROUTE TABLE PÚBLICA =====
resource "aws_route_table_association" "public" {
  count          = var.nat_gateway_enabled ? 1 : 0
  subnet_id      = aws_subnet.public[0].id
  route_table_id = aws_route_table.public[0].id
}

# ===== ROUTE TABLE PRIVADA (para subnets privadas com Lambda) =====
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

# ===== ASSOCIAÇÕES: SUBNETS PRIVADAS COM ROUTE TABLE PRIVADA =====
resource "aws_route_table_association" "private" {
  count          = var.nat_gateway_enabled ? length(var.subnet_ids) : 0
  subnet_id      = var.subnet_ids[count.index]
  route_table_id = aws_route_table.private[0].id
}

# ===== NETWORK ACL (opcional, para security) =====
resource "aws_network_acl" "private" {
  count      = var.nat_gateway_enabled ? 1 : 0
  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  # Inbound: Allow all from VPC CIDR
  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 0
    to_port    = 0
  }

  # Inbound: Allow ephemeral ports from NAT Gateway
  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Outbound: Allow all traffic
  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-nacl-private"
    }
  )
}