# ============================================================================
# DDL Setup for Redshift (Post-Terraform)
# ============================================================================
# This file demonstrates how to apply the DDL schema to Redshift
# Note: Terraform doesn't have a native "execute SQL" resource for Redshift
# So we use local-exec provisioner as a workaround
# ============================================================================

# Read the DDL file
locals {
  ddl_content = file("${path.module}/ddl.sql")
}

# Option 1: Local Exec Provisioner (requires psql installed on machine)
# This runs after Redshift is created
resource "null_resource" "redshift_ddl_setup" {
  provisioner "local-exec" {
    command = <<-EOT
      # Wait for Redshift to be ready
      sleep 30
      
      # Execute DDL script (requires psql installed)
      PGPASSWORD=${var.admin_password} psql \
        -h ${aws_redshiftserverless_workgroup.flight_data.endpoint[0].address} \
        -U ${var.admin_username} \
        -d ${var.database_name} \
        -f ${path.module}/ddl.sql \
        -v ON_ERROR_STOP=1
    EOT
    
    on_failure = continue  # Don't fail Terraform if this fails
  }

  depends_on = [aws_redshiftserverless_workgroup.flight_data]
}

# Option 2: Alternative - Store DDL in Systems Manager Parameter Store
# For later retrieval by CI/CD pipeline
resource "aws_ssm_parameter" "redshift_ddl" {
  name  = "/${var.project_name}/redshift/ddl-script"
  type  = "String"
  value = local.ddl_content

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-redshift-ddl"
      Environment = var.environment
    }
  )
}
