locals {
  name_prefix = "${var.project_name}-${var.environment}"

  colors = {
    success = "#2ca02c"
    warning = "#ff7f0e"
    error   = "#d62728"
    info    = "#1f77b4"
    purple  = "#9467bd"
    orange  = "#ff7f0e"
    cyan    = "#17becf"
  }

  period = 300  # 5 min

  # =====================================================================
  # WIDGETS DO DASHBOARD - Pipeline Completo
  # =====================================================================
  dashboard_widgets = flatten([

    # ── Header ──
    [{
      type       = "text"
      x          = 0
      y          = 0
      width      = 24
      height     = 1
      properties = {
        markdown = "# 🚀 ${upper(var.project_name)} — Pipeline de Ingestão\n**Ambiente:** ${upper(var.environment)} | **Região:** ${var.aws_region}"
      }
    }],

    # ═══════════════════════════════════════════════════════════════════
    # 🌐 API GATEWAY
    # ═══════════════════════════════════════════════════════════════════
    [for i in [0] : {
      type       = "text"
      x          = 0
      y          = 1
      width      = 24
      height     = 1
      properties = { markdown = "## 🌐 API Gateway" }
    } if var.api_gateway_stage != ""],

    # Count
    [for i in [0] : {
      type   = "metric"
      x      = 0
      y      = 2
      width  = 6
      height = 5
      properties = {
        title       = "📥 Requests"
        period      = local.period
        stat        = "Sum"
        region      = var.aws_region
        metrics     = [["AWS/ApiGateway", "Count", "ApiName", "${var.project_name}-flights-api", "Stage", var.api_gateway_stage, { label = "Count", color = local.colors.info }]]
        view        = "timeSeries"
        yAxis       = { left = { min = 0 } }
        annotations = { horizontal = [] }
      }
    } if var.api_gateway_stage != ""],

    # 4xx
    [for i in [0] : {
      type   = "metric"
      x      = 6
      y      = 2
      width  = 6
      height = 5
      properties = {
        title       = "⚠️ 4xx Errors"
        period      = local.period
        stat        = "Sum"
        region      = var.aws_region
        metrics     = [["AWS/ApiGateway", "4XXError", "ApiName", "${var.project_name}-flights-api", "Stage", var.api_gateway_stage, { label = "4xx", color = local.colors.warning }]]
        view        = "timeSeries"
        yAxis       = { left = { min = 0 } }
        annotations = { horizontal = [] }
      }
    } if var.api_gateway_stage != ""],

    # 5xx
    [for i in [0] : {
      type   = "metric"
      x      = 12
      y      = 2
      width  = 6
      height = 5
      properties = {
        title       = "❌ 5xx Errors"
        period      = local.period
        stat        = "Sum"
        region      = var.aws_region
        metrics     = [["AWS/ApiGateway", "5XXError", "ApiName", "${var.project_name}-flights-api", "Stage", var.api_gateway_stage, { label = "5xx", color = local.colors.error }]]
        view        = "timeSeries"
        yAxis       = { left = { min = 0 } }
        annotations = { horizontal = [] }
      }
    } if var.api_gateway_stage != ""],

    # Latency
    [for i in [0] : {
      type   = "metric"
      x      = 18
      y      = 2
      width  = 6
      height = 5
      properties = {
        title       = "⏱️ Latency (ms)"
        period      = local.period
        stat        = "p95"
        region      = var.aws_region
        metrics     = [["AWS/ApiGateway", "Latency", "ApiName", "${var.project_name}-flights-api", "Stage", var.api_gateway_stage, { label = "Latency", color = local.colors.purple }]]
        view        = "timeSeries"
        yAxis       = { left = { min = 0, label = "ms" } }
        annotations = { horizontal = [] }
      }
    } if var.api_gateway_stage != ""],

    # ═══════════════════════════════════════════════════════════════════
    # ⚡ LAMBDA FUNCTIONS
    # ═══════════════════════════════════════════════════════════════════
    [for i in [0] : {
      type       = "text"
      x          = 0
      y          = 7
      width      = 24
      height     = 1
      properties = { markdown = "## ⚡ Lambda — Authorizer / Flights" }
    } if length(var.lambda_functions) > 0],

    # Lambda invocations
    [for i in [0] : {
      type   = "metric"
      x      = 0
      y      = 8
      width  = 6
      height = 5
      properties = {
        title       = "📥 Invocações"
        period      = local.period
        stat        = "Sum"
        region      = var.aws_region
        metrics = [
          for f in var.lambda_functions : ["AWS/Lambda", "Invocations", "FunctionName", f.name, { label = f.name }]
        ]
        view        = "timeSeries"
        yAxis       = { left = { min = 0 } }
        annotations = { horizontal = [] }
      }
    } if length(var.lambda_functions) > 0],

    # Lambda errors
    [for i in [0] : {
      type   = "metric"
      x      = 6
      y      = 8
      width  = 6
      height = 5
      properties = {
        title       = "❌ Errors"
        period      = local.period
        stat        = "Sum"
        region      = var.aws_region
        metrics = [
          for f in var.lambda_functions : ["AWS/Lambda", "Errors", "FunctionName", f.name, { label = f.name, color = local.colors.error }]
        ]
        view        = "timeSeries"
        yAxis       = { left = { min = 0 } }
        annotations = { horizontal = [] }
      }
    } if length(var.lambda_functions) > 0],

    # Lambda duration
    [for i in [0] : {
      type   = "metric"
      x      = 12
      y      = 8
      width  = 6
      height = 5
      properties = {
        title       = "⏱️ Duration (ms) p95"
        period      = local.period
        stat        = "p95"
        region      = var.aws_region
        metrics = [
          for f in var.lambda_functions : ["AWS/Lambda", "Duration", "FunctionName", f.name, { label = f.name, color = local.colors.purple }]
        ]
        view        = "timeSeries"
        yAxis       = { left = { min = 0, label = "ms" } }
        annotations = { horizontal = [] }
      }
    } if length(var.lambda_functions) > 0],

    # Lambda throttles
    [for i in [0] : {
      type   = "metric"
      x      = 18
      y      = 8
      width  = 6
      height = 5
      properties = {
        title       = "🚫 Throttles"
        period      = local.period
        stat        = "Sum"
        region      = var.aws_region
        metrics = [
          for f in var.lambda_functions : ["AWS/Lambda", "Throttles", "FunctionName", f.name, { label = f.name, color = local.colors.warning }]
        ]
        view        = "timeSeries"
        yAxis       = { left = { min = 0 } }
        annotations = { horizontal = [] }
      }
    } if length(var.lambda_functions) > 0],

    # ═══════════════════════════════════════════════════════════════════
    # 📊 KINESIS STREAM — flights
    # ═══════════════════════════════════════════════════════════════════
    [for i in [0] : {
      type       = "text"
      x          = 0
      y          = 13
      width      = 24
      height     = 1
      properties = { markdown = "## 📊 Kinesis Stream — flights" }
    } if var.kinesis_stream_name != ""],

    # Records
    [for i in [0] : {
      type   = "metric"
      x      = 0
      y      = 14
      width  = 6
      height = 5
      properties = {
        title       = "📥 Records (in)"
        period      = local.period
        stat        = "Sum"
        region      = var.aws_region
        metrics     = [["AWS/Kinesis", "IncomingRecords", "StreamName", var.kinesis_stream_name, { label = "Count", color = local.colors.info }]]
        view        = "timeSeries"
        yAxis       = { left = { min = 0 } }
        annotations = { horizontal = [] }
      }
    } if var.kinesis_stream_name != ""],

    # Bytes
    [for i in [0] : {
      type   = "metric"
      x      = 6
      y      = 14
      width  = 6
      height = 5
      properties = {
        title       = "📦 Bytes"
        period      = local.period
        stat        = "Sum"
        region      = var.aws_region
        metrics     = [
          ["AWS/Kinesis", "IncomingBytes", "StreamName", var.kinesis_stream_name, { label = "In", color = local.colors.info }],
          ["AWS/Kinesis", "OutgoingBytes", "StreamName", var.kinesis_stream_name, { label = "Out", color = local.colors.success }],
        ]
        view        = "timeSeries"
        yAxis       = { left = { min = 0, label = "Bytes" } }
        annotations = { horizontal = [] }
      }
    } if var.kinesis_stream_name != ""],

    # Iterator Age
    [for i in [0] : {
      type   = "metric"
      x      = 12
      y      = 14
      width  = 6
      height = 5
      properties = {
        title       = "⏱️ Iterator Age (ms)"
        period      = local.period
        stat        = "Maximum"
        region      = var.aws_region
        metrics     = [["AWS/Kinesis", "GetRecords.IteratorAgeMilliseconds", "StreamName", var.kinesis_stream_name, { label = "ms", color = local.colors.error }]]
        view        = "timeSeries"
        yAxis       = { left = { min = 0, label = "ms" } }
        annotations = { horizontal = [] }
      }
    } if var.kinesis_stream_name != ""],

    # Throttling
    [for i in [0] : {
      type   = "metric"
      x      = 18
      y      = 14
      width  = 6
      height = 5
      properties = {
        title       = "⚠️ Throttling"
        period      = local.period
        stat        = "Sum"
        region      = var.aws_region
        metrics     = [
          ["AWS/Kinesis", "WriteProvisionedThroughputExceeded", "StreamName", var.kinesis_stream_name, { label = "Write", color = local.colors.error }],
          ["AWS/Kinesis", "ReadProvisionedThroughputExceeded", "StreamName", var.kinesis_stream_name, { label = "Read", color = local.colors.warning }],
        ]
        view        = "timeSeries"
        yAxis       = { left = { min = 0 } }
        annotations = { horizontal = [] }
      }
    } if var.kinesis_stream_name != ""],

    # ═══════════════════════════════════════════════════════════════════
    # 📊 KINESIS STREAM — flights_rt (enriquecido)
    # ═══════════════════════════════════════════════════════════════════
    [for i in [0] : {
      type       = "text"
      x          = 0
      y          = 19
      width      = 24
      height     = 1
      properties = { markdown = "## 📊 Kinesis Stream — flights_rt (enriquecido)" }
    } if var.kinesis_stream_name_rt != ""],

    # Records RT
    [for i in [0] : {
      type   = "metric"
      x      = 0
      y      = 20
      width  = 6
      height = 5
      properties = {
        title       = "📥 Records (in)"
        period      = local.period
        stat        = "Sum"
        region      = var.aws_region
        metrics     = [["AWS/Kinesis", "IncomingRecords", "StreamName", var.kinesis_stream_name_rt, { label = "Count", color = local.colors.info }]]
        view        = "timeSeries"
        yAxis       = { left = { min = 0 } }
        annotations = { horizontal = [] }
      }
    } if var.kinesis_stream_name_rt != ""],

    # Bytes RT
    [for i in [0] : {
      type   = "metric"
      x      = 6
      y      = 20
      width  = 6
      height = 5
      properties = {
        title       = "📦 Bytes"
        period      = local.period
        stat        = "Sum"
        region      = var.aws_region
        metrics     = [
          ["AWS/Kinesis", "IncomingBytes", "StreamName", var.kinesis_stream_name_rt, { label = "In", color = local.colors.info }],
          ["AWS/Kinesis", "OutgoingBytes", "StreamName", var.kinesis_stream_name_rt, { label = "Out", color = local.colors.success }],
        ]
        view        = "timeSeries"
        yAxis       = { left = { min = 0, label = "Bytes" } }
        annotations = { horizontal = [] }
      }
    } if var.kinesis_stream_name_rt != ""],

    # Iterator Age RT
    [for i in [0] : {
      type   = "metric"
      x      = 12
      y      = 20
      width  = 6
      height = 5
      properties = {
        title       = "⏱️ Iterator Age (ms)"
        period      = local.period
        stat        = "Maximum"
        region      = var.aws_region
        metrics     = [["AWS/Kinesis", "GetRecords.IteratorAgeMilliseconds", "StreamName", var.kinesis_stream_name_rt, { label = "ms", color = local.colors.error }]]
        view        = "timeSeries"
        yAxis       = { left = { min = 0, label = "ms" } }
        annotations = { horizontal = [] }
      }
    } if var.kinesis_stream_name_rt != ""],

    # Throttling RT
    [for i in [0] : {
      type   = "metric"
      x      = 18
      y      = 20
      width  = 6
      height = 5
      properties = {
        title       = "⚠️ Throttling"
        period      = local.period
        stat        = "Sum"
        region      = var.aws_region
        metrics     = [
          ["AWS/Kinesis", "WriteProvisionedThroughputExceeded", "StreamName", var.kinesis_stream_name_rt, { label = "Write", color = local.colors.error }],
          ["AWS/Kinesis", "ReadProvisionedThroughputExceeded", "StreamName", var.kinesis_stream_name_rt, { label = "Read", color = local.colors.warning }],
        ]
        view        = "timeSeries"
        yAxis       = { left = { min = 0 } }
        annotations = { horizontal = [] }
      }
    } if var.kinesis_stream_name_rt != ""],

    # ═══════════════════════════════════════════════════════════════════
    # 🧮 KINESIS DATA ANALYTICS (FLINK)
    # ═══════════════════════════════════════════════════════════════════
    [for i in [0] : {
      type       = "text"
      x          = 0
      y          = 25
      width      = 24
      height     = 1
      properties = { markdown = "## 🧮 Kinesis Data Analytics (Flink)" }
    } if var.kda_application_name != ""],

    # KPU Utilization
    [for i in [0] : {
      type   = "metric"
      x      = 0
      y      = 26
      width  = 6
      height = 5
      properties = {
        title       = "🧠 KPU Utilization"
        period      = local.period
        stat        = "Average"
        region      = var.aws_region
        metrics     = [["AWS/KinesisAnalytics", "KPUs", "Application", var.kda_application_name, { label = "KPU Count", color = local.colors.purple }]]
        view        = "timeSeries"
        yAxis       = { left = { min = 0, max = 100, label = "%" } }
        annotations = { horizontal = [] }
      }
    } if var.kda_application_name != ""],

    # Messages in
    [for i in [0] : {
      type   = "metric"
      x      = 6
      y      = 26
      width  = 6
      height = 5
      properties = {
        title       = "📥 Messages In"
        period      = local.period
        stat        = "Sum"
        region      = var.aws_region
        metrics     = [["AWS/KinesisAnalytics", "numRecordsIn", "Application", var.kda_application_name, { label = "In", color = local.colors.info }]]
        view        = "timeSeries"
        yAxis       = { left = { min = 0 } }
        annotations = { horizontal = [] }
      }
    } if var.kda_application_name != ""],

    # Messages out
    [for i in [0] : {
      type   = "metric"
      x      = 12
      y      = 26
      width  = 6
      height = 5
      properties = {
        title       = "📤 Messages Out"
        period      = local.period
        stat        = "Sum"
        region      = var.aws_region
        metrics     = [["AWS/KinesisAnalytics", "numRecordsOut", "Application", var.kda_application_name, { label = "Out", color = local.colors.success }]]
        view        = "timeSeries"
        yAxis       = { left = { min = 0 } }
        annotations = { horizontal = [] }
      }
    } if var.kda_application_name != ""],

    # MillisBehindLatest
    [for i in [0] : {
      type   = "metric"
      x      = 18
      y      = 26
      width  = 6
      height = 5
      properties = {
        title       = "⏱️ MillisBehindLatest"
        period      = local.period
        stat        = "Maximum"
        region      = var.aws_region
        metrics     = [["AWS/KinesisAnalytics", "millisBehindLatest", "Application", var.kda_application_name, { label = "ms", color = local.colors.error }]]
        view        = "timeSeries"
        yAxis       = { left = { min = 0, label = "ms" } }
        annotations = { horizontal = [] }
      }
    } if var.kda_application_name != ""],

    # ═══════════════════════════════════════════════════════════════════
    # 🗄️ Aurora Serverless v2
    # ═══════════════════════════════════════════════════════════════════
    [for i in [0] : {
      type       = "text"
      x          = 0
      y          = 31
      width      = 24
      height     = 1
      properties = { markdown = "## 🗄️ Aurora Serverless v2 — PostgreSQL" }
    } if var.aurora_instance_identifier != ""],

    # Database Connections
    [for i in [0] : {
      type   = "metric"
      x      = 0
      y      = 32
      width  = 6
      height = 5
      properties = {
        title       = "🔗 Conexões Ativas"
        period      = local.period
        stat        = "Average"
        region      = var.aws_region
        metrics     = [["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.aurora_instance_identifier, { label = "Conexões", color = local.colors.cyan }]]
        view        = "timeSeries"
        yAxis       = { left = { min = 0 } }
        annotations = { horizontal = [] }
      }
    } if var.aurora_instance_identifier != ""],

    # Read/Write IOPS
    [for i in [0] : {
      type   = "metric"
      x      = 6
      y      = 32
      width  = 6
      height = 5
      properties = {
        title       = "💾 IOPS (Leitura/Escrita)"
        period      = local.period
        stat        = "Average"
        region      = var.aws_region
        metrics     = [
          ["AWS/RDS", "ReadIOPS", "DBInstanceIdentifier", var.aurora_instance_identifier, { label = "Read", color = local.colors.info }],
          ["AWS/RDS", "WriteIOPS", "DBInstanceIdentifier", var.aurora_instance_identifier, { label = "Write", color = local.colors.success }],
        ]
        view        = "timeSeries"
        yAxis       = { left = { min = 0, label = "IOPS" } }
        annotations = { horizontal = [] }
      }
    } if var.aurora_instance_identifier != ""],

    # Read/Write Latency
    [for i in [0] : {
      type   = "metric"
      x      = 12
      y      = 32
      width  = 6
      height = 5
      properties = {
        title       = "⏱️ Latência (ms)"
        period      = local.period
        stat        = "Average"
        region      = var.aws_region
        metrics     = [
          ["AWS/RDS", "ReadLatency", "DBInstanceIdentifier", var.aurora_instance_identifier, { label = "Read ms", color = local.colors.info }],
          ["AWS/RDS", "WriteLatency", "DBInstanceIdentifier", var.aurora_instance_identifier, { label = "Write ms", color = local.colors.success }],
        ]
        view        = "timeSeries"
        yAxis       = { left = { min = 0, label = "ms" } }
        annotations = { horizontal = [] }
      }
    } if var.aurora_instance_identifier != ""],

    # Free Storage Space (Aurora auto-scaling — mostra o cluster storage)
    [for i in [0] : {
      type   = "metric"
      x      = 18
      y      = 32
      width  = 6
      height = 5
      properties = {
        title       = "💿 Volume do Cluster (Bytes)"
        period      = local.period
        stat        = "Average"
        region      = var.aws_region
        metrics     = [["AWS/RDS", "VolumeBytesUsed", "DBClusterIdentifier", var.aurora_cluster_identifier, { label = "Bytes", color = local.colors.purple }]]
        view        = "timeSeries"
        yAxis       = { left = { min = 0, label = "Bytes" } }
        annotations = { horizontal = [] }
      }
    } if var.aurora_cluster_identifier != ""],

    # ═══════════════════════════════════════════════════════════════════
    # 🔄 DMS Serverless (Aurora → S3)
    # ═══════════════════════════════════════════════════════════════════
    [for i in [0] : {
      type       = "text"
      x          = 0
      y          = 37
      width      = 24
      height     = 1
      properties = { markdown = "## 🔄 DMS Serverless — Aurora → S3 (Lake)" }
    } if var.dms_serverless_config_id != ""],

    # CDC Changes + Bytes
    [for i in [0] : {
      type   = "metric"
      x      = 0
      y      = 38
      width  = 12
      height = 5
      properties = {
        title       = "🔄 CDC Incoming"
        period      = local.period
        stat        = "Sum"
        region      = var.aws_region
        metrics     = [
          ["AWS/DMS", "CDCIncomingChanges", "ReplicationConfigIdentifier", var.dms_serverless_config_id, { label = "Changes", color = local.colors.info }],
          ["AWS/DMS", "CDCIncomingBytes", "ReplicationConfigIdentifier", var.dms_serverless_config_id, { label = "Bytes", color = local.colors.cyan }],
        ]
        view        = "timeSeries"
        yAxis       = { left = { min = 0 } }
        annotations = { horizontal = [] }
      }
    } if var.dms_serverless_config_id != ""],

    # Latency
    [for i in [0] : {
      type   = "metric"
      x      = 12
      y      = 38
      width  = 6
      height = 5
      properties = {
        title       = "⏱️ Latency (seg)"
        period      = local.period
        stat        = "Average"
        region      = var.aws_region
        metrics     = [
          ["AWS/DMS", "CDCLatencySource", "ReplicationConfigIdentifier", var.dms_serverless_config_id, { label = "Source", color = local.colors.warning }],
          ["AWS/DMS", "CDCLatencyTarget", "ReplicationConfigIdentifier", var.dms_serverless_config_id, { label = "Target", color = local.colors.error }],
        ]
        view        = "timeSeries"
        yAxis       = { left = { min = 0, label = "seg" } }
        annotations = { horizontal = [] }
      }
    } if var.dms_serverless_config_id != ""],

    # CDC Errors
    [for i in [0] : {
      type   = "metric"
      x      = 18
      y      = 38
      width  = 6
      height = 5
      properties = {
        title       = "❌ CDC Errors"
        period      = local.period
        stat        = "Sum"
        region      = var.aws_region
        metrics     = [
          ["AWS/DMS", "CDCChangesFailed", "ReplicationConfigIdentifier", var.dms_serverless_config_id, { label = "CDC Err", color = local.colors.error }],
        ]
        view        = "timeSeries"
        yAxis       = { left = { min = 0 } }
        annotations = { horizontal = [] }
      }
    } if var.dms_serverless_config_id != ""],

    # ── Full Load metrics ───────────────────────────────────────────────
    # Full Load Throughput
    [for i in [0] : {
      type   = "metric"
      x      = 0
      y      = 43
      width  = 8
      height = 5
      properties = {
        title       = "📊 FL Throughput (MB/s)"
        period      = local.period
        stat        = "Average"
        region      = var.aws_region
        metrics     = [["AWS/DMS", "FullLoadThroughputBandwidth", "ReplicationConfigIdentifier", var.dms_serverless_config_id, { label = "MB/s", color = local.colors.cyan }]]
        view        = "timeSeries"
        yAxis       = { left = { min = 0, label = "MB/s" } }
        annotations = { horizontal = [] }
      }
    } if var.dms_serverless_config_id != ""],

    # Full Load Rows/s
    [for i in [0] : {
      type   = "metric"
      x      = 8
      y      = 43
      width  = 8
      height = 5
      properties = {
        title       = "📊 FL Rows/s"
        period      = local.period
        stat        = "Average"
        region      = var.aws_region
        metrics     = [["AWS/DMS", "FullLoadThroughputRows", "ReplicationConfigIdentifier", var.dms_serverless_config_id, { label = "Rows/s", color = local.colors.success }]]
        view        = "timeSeries"
        yAxis       = { left = { min = 0 } }
        annotations = { horizontal = [] }
      }
    } if var.dms_serverless_config_id != ""],

    # Full Load Errors
    [for i in [0] : {
      type   = "metric"
      x      = 16
      y      = 43
      width  = 8
      height = 5
      properties = {
        title       = "⚠️ FL Errors"
        period      = local.period
        stat        = "Sum"
        region      = var.aws_region
        metrics     = [["AWS/DMS", "FullLoadErrors", "ReplicationConfigIdentifier", var.dms_serverless_config_id, { label = "FL Err", color = local.colors.warning }]]
        view        = "timeSeries"
        yAxis       = { left = { min = 0 } }
        annotations = { horizontal = [] }
      }
    } if var.dms_serverless_config_id != ""],

    # ═══════════════════════════════════════════════════════════════════
    # 📬 SQS DLQ
    # ═══════════════════════════════════════════════════════════════════
    [for i in [0] : {
      type       = "text"
      x          = 0
      y          = 48
      width      = 24
      height     = 1
      properties = { markdown = "## 📬 SQS DLQ (Dead Letter Queue)" }
    } if var.sqs_queue_name != ""],

    # Messages Sent
    [for i in [0] : {
      type   = "metric"
      x      = 0
      y      = 49
      width  = 8
      height = 5
      properties = {
        title       = "📥 Messages Sent"
        period      = local.period
        stat        = "Sum"
        region      = var.aws_region
        metrics     = [["AWS/SQS", "NumberOfMessagesSent", "QueueName", var.sqs_queue_name, { label = "Sent", color = local.colors.info }]]
        view        = "timeSeries"
        yAxis       = { left = { min = 0 } }
        annotations = { horizontal = [] }
      }
    } if var.sqs_queue_name != ""],

    # Messages Received
    [for i in [0] : {
      type   = "metric"
      x      = 8
      y      = 49
      width  = 8
      height = 5
      properties = {
        title       = "📤 Messages Received"
        period      = local.period
        stat        = "Sum"
        region      = var.aws_region
        metrics     = [["AWS/SQS", "NumberOfMessagesReceived", "QueueName", var.sqs_queue_name, { label = "Received", color = local.colors.success }]]
        view        = "timeSeries"
        yAxis       = { left = { min = 0 } }
        annotations = { horizontal = [] }
      }
    } if var.sqs_queue_name != ""],

    # Age
    [for i in [0] : {
      type   = "metric"
      x      = 16
      y      = 49
      width  = 8
      height = 5
      properties = {
        title       = "⏱️ Idade Mensagem Mais Antiga"
        period      = local.period
        stat        = "Maximum"
        region      = var.aws_region
        metrics     = [["AWS/SQS", "ApproximateAgeOfOldestMessage", "QueueName", var.sqs_queue_name, { label = "seg", color = local.colors.error }]]
        view        = "timeSeries"
        yAxis       = { left = { min = 0, label = "seg" } }
        annotations = { horizontal = [] }
      }
    } if var.sqs_queue_name != ""],

    # ═══════════════════════════════════════════════════════════════════
    # 💾 S3 LANDING (métricas DMS)
    # ═══════════════════════════════════════════════════════════════════
    [for i in [0] : {
      type       = "text"
      x          = 0
      y          = 54
      width      = 24
      height     = 1
      properties = { markdown = "## 💾 S3 Landing — Lake" }
    } if var.s3_landing_bucket_name != ""],

    # Bucket Size — time series (evolução 1 ano)
    [for i in [0] : {
      type   = "metric"
      x      = 0
      y      = 55
      width  = 12
      height = 5
      properties = {
        title       = "📦 Evolução Bucket Size (Bytes)"
        period      = 86400  # 1 dia — métrica diária
        stat        = "Average"
        region      = var.aws_region
        metrics     = [["AWS/S3", "BucketSizeBytes", "BucketName", var.s3_landing_bucket_name, "StorageType", "StandardStorage", { label = "Size", color = local.colors.info }]]
        view        = "timeSeries"
        yAxis       = { left = { min = 0, label = "Bytes" } }
        annotations = { horizontal = [] }
      }
    } if var.s3_landing_bucket_name != ""],

    # Object Count — time series (evolução 1 ano)
    [for i in [0] : {
      type   = "metric"
      x      = 12
      y      = 55
      width  = 12
      height = 5
      properties = {
        title       = "📄 Evolução Number of Objects"
        period      = 86400  # 1 dia
        stat        = "Average"
        region      = var.aws_region
        metrics     = [["AWS/S3", "NumberOfObjects", "BucketName", var.s3_landing_bucket_name, "StorageType", "AllStorageTypes", { label = "Objects", color = local.colors.success }]]
        view        = "timeSeries"
        yAxis       = { left = { min = 0 } }
        annotations = { horizontal = [] }
      }
    } if var.s3_landing_bucket_name != ""],

    # Note — métricas diárias
    [for i in [0] : {
      type       = "text"
      x          = 0
      y          = 60
      width      = 24
      height     = 1
      properties = { markdown = "⚠️ **Nota:** `BucketSizeBytes` e `NumberOfObjects` são métricas **diárias** (publicadas 1×/dia). Pode levar até 24h para o primeiro ponto aparecer após os dados começarem a chegar no bucket." }
    } if var.s3_landing_bucket_name != ""]

  ])
}