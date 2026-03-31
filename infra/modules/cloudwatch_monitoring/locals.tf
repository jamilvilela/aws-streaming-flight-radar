locals {
  # Prefixo comum para nomes de recursos
  name_prefix = "${var.project_name}-${var.environment}"
  
  # Dimensões comuns
  kinesis_dimensions = {
    StreamName = var.kinesis_stream_name
  }
  
  firehose_s3_dimensions = var.firehose_s3_name != "" ? {
    DeliveryStreamName = var.firehose_s3_name
  } : {}
  
  firehose_opensearch_dimensions = var.firehose_opensearch_name != "" ? {
    DeliveryStreamName = var.firehose_opensearch_name
  } : {}
  
  # ✅ Dimensões OpenSearch Serverless
  opensearch_serverless_dimensions = var.opensearch_collection_name != "" ? {
    CollectionName = var.opensearch_collection_name
  } : {}
  
  # ✅ Dimensões OpenSearch Cluster
  opensearch_cluster_dimensions = var.opensearch_domain_name != "" ? {
    DomainName = var.opensearch_domain_name
    ClientId   = "all"
  } : {}
  
  # Cores para widgets do dashboard
  colors = {
    success = "#2ca02c"
    warning = "#ff7f0e"
    error   = "#d62728"
    info    = "#1f77b4"
  }
  
  # Períodos padrão para métricas
  periods = {
    real_time = 60
    short     = 300
    medium    = 900
    long      = 3600
  }
  
  # =====================================================================
  # WIDGETS DO DASHBOARD - Padronizados para evitar erro de tipo
  # =====================================================================
  dashboard_widgets = flatten([
    
    # Header (sempre presente)
    [{
      type   = "text"
      x      = 0
      y      = 0
      width  = 24
      height = 1
      properties = {
        markdown = "# 🚀 ${upper(var.project_name)} - Pipeline\n**Ambiente:** ${upper(var.environment)}"
      }
    }],
    
    # Kinesis Widgets
    [for i in [0] : {
      type   = "metric"
      x      = 0
      y      = 1
      width  = 12
      height = 6
      properties = {
        title       = "📥 Registros Entrando"
        period      = local.periods.short
        stat        = "Sum"
        region      = var.aws_region
        metrics     = [["AWS/Kinesis", "IncomingRecords", "StreamName", var.kinesis_stream_name, { label = "Count", color = local.colors.info }]]
        view        = "timeSeries"
        yAxis       = { left = { min = 0, label = "Reg/min" } }
        annotations = { horizontal = [] }
      }
    } if var.kinesis_stream_name != ""],
    
    [for i in [0] : {
      type   = "metric"
      x      = 12
      y      = 1
      width  = 12
      height = 6
      properties = {
        title  = "⏱️ Iterator Age"
        period = local.periods.short
        stat   = "Maximum"
        region = var.aws_region
        metrics = [["AWS/Kinesis", "GetRecords.IteratorAgeMilliseconds", "StreamName", var.kinesis_stream_name, { label = "ms", color = local.colors.error }]]
        view        = "timeSeries"
        yAxis       = { left = { min = 0, label = "ms" } }
        annotations = { horizontal = [{ label = "Threshold", value = var.alarm_thresholds.kinesis_iterator_age_ms, color = local.colors.error }] }
      }
    } if var.kinesis_stream_name != ""],
    
    [for i in [0] : {
      type   = "metric"
      x      = 0
      y      = 7
      width  = 12
      height = 6
      properties = {
        title  = "📊 Throughput"
        period = local.periods.short
        stat   = "Sum"
        region = var.aws_region
        metrics = [
          ["AWS/Kinesis", "IncomingBytes", "StreamName", var.kinesis_stream_name, { label = "In", color = local.colors.info }],
          ["AWS/Kinesis", "OutgoingBytes", "StreamName", var.kinesis_stream_name, { label = "Out", color = local.colors.success }]
        ]
        view        = "timeSeries"
        yAxis       = { left = { min = 0, label = "Bytes" } }
        annotations = { horizontal = [] }
      }
    } if var.kinesis_stream_name != ""],
    
    [for i in [0] : {
      type   = "metric"
      x      = 12
      y      = 7
      width  = 12
      height = 6
      properties = {
        title  = "⚠️ Throttling"
        period = local.periods.short
        stat   = "Sum"
        region = var.aws_region
        metrics = [
          ["AWS/Kinesis", "WriteProvisionedThroughputExceeded", "StreamName", var.kinesis_stream_name, { label = "Write", color = local.colors.error }],
          ["AWS/Kinesis", "ReadProvisionedThroughputExceeded", "StreamName", var.kinesis_stream_name, { label = "Read", color = local.colors.warning }]
        ]
        view        = "timeSeries"
        yAxis       = { left = { min = 0, label = "Count" } }
        annotations = { horizontal = [] }
      }
    } if var.kinesis_stream_name != ""],
    
    # Firehose S3 Widgets
    [for i in [0] : {
      type   = "text"
      x      = 0
      y      = var.kinesis_stream_name != "" ? 13 : 1
      width  = 24
      height = 1
      properties = { markdown = "## 🪣 Firehose → S3" }
    } if var.firehose_s3_name != ""],
    
    [for i in [0] : {
      type   = "metric"
      x      = 0
      y      = (var.kinesis_stream_name != "" ? 13 : 1) + 1
      width  = 8
      height = 6
      properties = {
        title       = "✅ Sucesso"
        period      = local.periods.short
        stat        = "Sum"
        region      = var.aws_region
        metrics     = [["AWS/Firehose", "DeliveryToS3.Success", "DeliveryStreamName", var.firehose_s3_name, { label = "OK", color = local.colors.success }]]
        view        = "timeSeries"
        yAxis       = { left = { min = 0 } }
        annotations = { horizontal = [] }
      }
    } if var.firehose_s3_name != ""],
    
    [for i in [0] : {
      type   = "metric"
      x      = 8
      y      = (var.kinesis_stream_name != "" ? 13 : 1) + 1
      width  = 8
      height = 6
      properties = {
        title       = "❌ Falhas"
        period      = local.periods.short
        stat        = "Sum"
        region      = var.aws_region
        metrics     = [["AWS/Firehose", "DeliveryToS3.Failed", "DeliveryStreamName", var.firehose_s3_name, { label = "Fail", color = local.colors.error }]]
        view        = "timeSeries"
        yAxis       = { left = { min = 0 } }
        annotations = { horizontal = [] }
      }
    } if var.firehose_s3_name != ""],
    
    [for i in [0] : {
      type   = "metric"
      x      = 16
      y      = (var.kinesis_stream_name != "" ? 13 : 1) + 1
      width  = 8
      height = 6
      properties = {
        title       = "📈 Taxa %"
        period      = local.periods.short
        stat        = "Average"
        region      = var.aws_region
        metrics     = [["AWS/Firehose", "DeliveryToS3.Success", "DeliveryStreamName", var.firehose_s3_name, { label = "%", color = local.colors.info }]]
        view        = "timeSeries"
        yAxis       = { left = { min = 0, max = 100, label = "%" } }
        annotations = { horizontal = [] }
      }
    } if var.firehose_s3_name != ""],
    
    # Firehose OpenSearch Widgets
    [for i in [0] : {
      type   = "text"
      x      = 0
      y      = (var.kinesis_stream_name != "" ? 13 : 1) + (var.firehose_s3_name != "" ? 7 : 0)
      width  = 24
      height = 1
      properties = { markdown = "## 🔍 Firehose → OpenSearch" }
    } if var.firehose_opensearch_name != ""],
    
    [for i in [0] : {
      type   = "metric"
      x      = 0
      y      = (var.kinesis_stream_name != "" ? 14 : 2) + (var.firehose_s3_name != "" ? 7 : 0)
      width  = 8
      height = 6
      properties = {
        title       = "✅ Index"
        period      = local.periods.short
        stat        = "Sum"
        region      = var.aws_region
        metrics     = [["AWS/Firehose", "DeliveryToOpenSearch.Success", "DeliveryStreamName", var.firehose_opensearch_name, { label = "OK", color = local.colors.success }]]
        view        = "timeSeries"
        yAxis       = { left = { min = 0 } }
        annotations = { horizontal = [] }
      }
    } if var.firehose_opensearch_name != ""],
    
    [for i in [0] : {
      type   = "metric"
      x      = 8
      y      = (var.kinesis_stream_name != "" ? 14 : 2) + (var.firehose_s3_name != "" ? 7 : 0)
      width  = 8
      height = 6
      properties = {
        title  = "❌ Falhas"
        period = local.periods.short
        stat   = "Sum"
        region = var.aws_region
        metrics = [
          ["AWS/Firehose", "DeliveryToOpenSearch.Failed", "DeliveryStreamName", var.firehose_opensearch_name, { label = "Fail", color = local.colors.error }],
          ["AWS/Firehose", "Documents.Dropped", "DeliveryStreamName", var.firehose_opensearch_name, { label = "Drop", color = local.colors.warning }]
        ]
        view        = "timeSeries"
        yAxis       = { left = { min = 0 } }
        annotations = { horizontal = [] }
      }
    } if var.firehose_opensearch_name != ""],
    
    [for i in [0] : {
      type   = "metric"
      x      = 16
      y      = (var.kinesis_stream_name != "" ? 14 : 2) + (var.firehose_s3_name != "" ? 7 : 0)
      width  = 8
      height = 6
      properties = {
        title       = "⏱️ Latência"
        period      = local.periods.short
        stat        = "Average"
        region      = var.aws_region
        metrics     = [["AWS/Firehose", "DeliveryToOpenSearch.SuccessLatency", "DeliveryStreamName", var.firehose_opensearch_name, { label = "ms", color = local.colors.info }]]
        view        = "timeSeries"
        yAxis       = { left = { min = 0, label = "ms" } }
        annotations = { horizontal = [] }
      }
    } if var.firehose_opensearch_name != ""],
    
    # Lambda Widgets
    flatten([
      for idx, f in var.lambda_functions : [
        {
          type   = "text"
          x      = 0
          y      = (var.kinesis_stream_name != "" ? 13 : 1) + (var.firehose_s3_name != "" ? 7 : 0) + (var.firehose_opensearch_name != "" ? 7 : 0) + (idx * 6)
          width  = 24
          height = 1
          properties = { markdown = "### ⚡ ${f.name}" }
        },
        {
          type   = "metric"
          x      = 0
          y      = (var.kinesis_stream_name != "" ? 14 : 2) + (var.firehose_s3_name != "" ? 7 : 0) + (var.firehose_opensearch_name != "" ? 7 : 0) + (idx * 6) + 1
          width  = 8
          height = 6
          properties = {
            title       = "📊 Invocações"
            period      = local.periods.short
            stat        = "Sum"
            region      = var.aws_region
            metrics     = [["AWS/Lambda", "Invocations", "FunctionName", f.name, { label = "Count", color = local.colors.info }]]
            view        = "timeSeries"
            yAxis       = { left = { min = 0 } }
            annotations = { horizontal = [] }
          }
        },
        {
          type   = "metric"
          x      = 8
          y      = (var.kinesis_stream_name != "" ? 14 : 2) + (var.firehose_s3_name != "" ? 7 : 0) + (var.firehose_opensearch_name != "" ? 7 : 0) + (idx * 6) + 1
          width  = 8
          height = 6
          properties = {
            title       = "❌ Erros"
            period      = local.periods.short
            stat        = "Sum"
            region      = var.aws_region
            metrics     = [["AWS/Lambda", "Errors", "FunctionName", f.name, { label = "Err", color = local.colors.error }]]
            view        = "timeSeries"
            yAxis       = { left = { min = 0 } }
            annotations = { horizontal = [] }
          }
        },
        {
          type   = "metric"
          x      = 16
          y      = (var.kinesis_stream_name != "" ? 14 : 2) + (var.firehose_s3_name != "" ? 7 : 0) + (var.firehose_opensearch_name != "" ? 7 : 0) + (idx * 6) + 1
          width  = 8
          height = 6
          properties = {
            title       = "⏱️ Duração Max"
            period      = local.periods.short
            stat        = "Maximum"
            region      = var.aws_region
            metrics     = [["AWS/Lambda", "Duration", "FunctionName", f.name, { label = "Max ms", color = local.colors.warning }]]
            view        = "timeSeries"
            yAxis       = { left = { min = 0, label = "ms" } }
            annotations = { horizontal = [] }
          }
        }
      ] if length(var.lambda_functions) > 0
    ]),
    
    # =====================================================================
    # OPENSEARCH SERVERLESS WIDGETS 
    # =====================================================================
    [for i in [0] : {
      type   = "text"
      x      = 0
      y      = (var.kinesis_stream_name != "" ? 13 : 1) + (var.firehose_s3_name != "" ? 7 : 0) + (var.firehose_opensearch_name != "" ? 7 : 0) + (length(var.lambda_functions) > 0 ? 1 + (length(var.lambda_functions) * 6) : 0)
      width  = 24
      height = 1
      properties = { markdown = "## 🗄️ OpenSearch Serverless: ${var.opensearch_collection_name}" }
    } if var.opensearch_type == "serverless" && var.opensearch_collection_name != ""],
    
    [for i in [0] : {
      type   = "metric"
      x      = 0
      y      = (var.kinesis_stream_name != "" ? 14 : 2) + (var.firehose_s3_name != "" ? 7 : 0) + (var.firehose_opensearch_name != "" ? 7 : 0) + (length(var.lambda_functions) > 0 ? 1 + (length(var.lambda_functions) * 6) : 0)
      width  = 8
      height = 6
      properties = {
        title  = "💻 Search OCU %"
        period = local.periods.short
        stat   = "Average"
        region = var.aws_region
        metrics = [["AWS/AOSS", "SearchOCUUtilization", "CollectionName", var.opensearch_collection_name, { label = "Search OCU", color = local.colors.info }]]
        view        = "timeSeries"
        yAxis       = { left = { min = 0, max = 100, label = "%" } }
        annotations = { horizontal = [{ label = "Threshold ${var.alarm_thresholds.opensearch_ocu_utilization}%", value = var.alarm_thresholds.opensearch_ocu_utilization, color = local.colors.error }] }
      }
    } if var.opensearch_type == "serverless" && var.opensearch_collection_name != ""],
    
    [for i in [0] : {
      type   = "metric"
      x      = 8
      y      = (var.kinesis_stream_name != "" ? 14 : 2) + (var.firehose_s3_name != "" ? 7 : 0) + (var.firehose_opensearch_name != "" ? 7 : 0) + (length(var.lambda_functions) > 0 ? 1 + (length(var.lambda_functions) * 6) : 0)
      width  = 8
      height = 6
      properties = {
        title  = "📈 Indexing OCU %"
        period = local.periods.short
        stat   = "Average"
        region = var.aws_region
        metrics = [["AWS/AOSS", "IndexingOCUUtilization", "CollectionName", var.opensearch_collection_name, { label = "Index OCU", color = local.colors.warning }]]
        view        = "timeSeries"
        yAxis       = { left = { min = 0, max = 100, label = "%" } }
        annotations = { horizontal = [{ label = "Threshold ${var.alarm_thresholds.opensearch_ocu_utilization}%", value = var.alarm_thresholds.opensearch_ocu_utilization, color = local.colors.error }] }
      }
    } if var.opensearch_type == "serverless" && var.opensearch_collection_name != ""],
    
    [for i in [0] : {
      type   = "metric"
      x      = 16
      y      = (var.kinesis_stream_name != "" ? 14 : 2) + (var.firehose_s3_name != "" ? 7 : 0) + (var.firehose_opensearch_name != "" ? 7 : 0) + (length(var.lambda_functions) > 0 ? 1 + (length(var.lambda_functions) * 6) : 0)
      width  = 8
      height = 6
      properties = {
        title  = "📊 Index/Search Rate"
        period = local.periods.short
        stat   = "Average"
        region = var.aws_region
        metrics = [
          ["AWS/AOSS", "IndexingRate", "CollectionName", var.opensearch_collection_name, { label = "Idx/s", color = local.colors.success }],
          ["AWS/AOSS", "SearchRequestRate", "CollectionName", var.opensearch_collection_name, { label = "Src/s", color = local.colors.info }]
        ]
        view        = "timeSeries"
        yAxis       = { left = { min = 0, label = "Ops/s" } }
        annotations = { horizontal = [] }
      }
    } if var.opensearch_type == "serverless" && var.opensearch_collection_name != ""],
  ])
}