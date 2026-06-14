resource "aws_db_subnet_group" "this" {
  name        = "${var.project_name}-rds-subnet-group"
  description = "Subnet group for ${var.project_name} RDS PostgreSQL"
  subnet_ids  = var.subnet_ids

  tags = merge(var.tags, {
    Name = "${var.project_name}-rds-subnet-group"
  })
}

resource "aws_db_parameter_group" "this" {
  name        = "${var.project_name}-rds-pg"
  family      = "postgres18"
  description = "Parameter group for ${var.project_name} RDS PostgreSQL"

  tags = merge(var.tags, {
    Name = "${var.project_name}-rds-pg"
  })
}

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for ${var.project_name} RDS PostgreSQL"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "PostgreSQL access"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-rds-sg"
  })
}

resource "aws_db_instance" "this" {
  identifier     = "${var.project_name}-postgres"
  db_name        = var.db_name
  engine         = "postgres"
  engine_version = "18.1"
  instance_class = var.instance_class

  username = var.admin_username
  password = var.admin_password
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.this.name
  parameter_group_name   = aws_db_parameter_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.max_allocated_storage_gb
  storage_type          = "gp3"
  storage_encrypted     = true

  backup_retention_period = var.backup_retention_days
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window
  snapshot_identifier   = var.snapshot_identifier
  copy_tags_to_snapshot = true
  skip_final_snapshot   = var.skip_final_snapshot
  deletion_protection   = var.deletion_protection
  publicly_accessible   = var.publicly_accessible

  enabled_cloudwatch_logs_exports = ["postgresql"]

  lifecycle {
    ignore_changes = [snapshot_identifier]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-postgres"
  })
}

resource "aws_cloudwatch_log_group" "postgres" {
  name              = "/aws/rds/${var.project_name}-postgres"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# ---------------------------------------------------------------------------
# Read replicas
# ---------------------------------------------------------------------------
resource "aws_db_instance" "replica" {
  for_each = { for i, r in var.read_replicas : "replica-${i + 1}" => r }

  identifier = "${var.project_name}-postgres-${each.key}"

  replicate_source_db = aws_db_instance.this.arn

  instance_class       = each.value.instance_class != null ? each.value.instance_class : var.instance_class
  allocated_storage    = each.value.allocated_storage_gb != null ? each.value.allocated_storage_gb : var.allocated_storage_gb
  publicly_accessible  = each.value.publicly_accessible

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.this.name

  storage_type      = "gp3"
  storage_encrypted = true
  port              = 5432

  copy_tags_to_snapshot = true
  skip_final_snapshot   = var.skip_final_snapshot
  deletion_protection   = var.deletion_protection

  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = merge(var.tags, {
    Name = "${var.project_name}-postgres-${each.key}"
  })
}

resource "aws_cloudwatch_log_group" "replica" {
  for_each = { for i, r in var.read_replicas : "replica-${i + 1}" => r }

  name              = "/aws/rds/${var.project_name}-postgres-${each.key}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}
