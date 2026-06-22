# =============================================================================
# CLOUDWATCH DASHBOARD - Pipeline Completo
# =============================================================================

resource "aws_cloudwatch_dashboard" "streaming_pipeline" {
  dashboard_name = "${local.name_prefix}-streaming-pipeline"

  dashboard_body = jsonencode({
    start   = "-P7D"
    widgets = local.dashboard_widgets
  })
}
