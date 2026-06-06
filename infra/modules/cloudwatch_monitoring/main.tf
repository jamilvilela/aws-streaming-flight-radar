# =============================================================================
# ALARMES - KINESIS STREAM
# =============================================================================

# Iterator Age - indica backlog no processamento
resource "aws_cloudwatch_metric_alarm" "kinesis_iterator_age" {
  alarm_name          = "${local.name_prefix}-kinesis-high-iterator-age"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "GetRecords.IteratorAgeMilliseconds"
  namespace           = "AWS/Kinesis"
  period              = var.alarm_period_seconds
  statistic           = "Maximum"
  threshold           = var.alarm_thresholds.kinesis_iterator_age_ms
  alarm_description   = "Alerta: Registros não processados por mais de ${var.alarm_thresholds.kinesis_iterator_age_ms / 1000}s no stream"
  treat_missing_data  = "notBreaching"

  dimensions = local.kinesis_dimensions

  tags = merge(var.tags, {
    AlarmType = "KinesisIteratorAge"
    Severity  = "High"
  })

  alarm_actions = var.sns_alarm_topic_arn != "" ? [var.sns_alarm_topic_arn] : []
}

# Sem registros entrando - possível interrupção no produtor
resource "aws_cloudwatch_metric_alarm" "kinesis_no_incoming_records" {
  alarm_name          = "${local.name_prefix}-kinesis-no-incoming-records"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "IncomingRecords"
  namespace           = "AWS/Kinesis"
  period              = 600 # 10 minutos para esta métrica
  statistic           = "Sum"
  threshold           = var.alarm_thresholds.kinesis_no_records_minutes
  alarm_description   = "Alerta: Nenhum registro recebido no stream por 10+ minutos"
  treat_missing_data  = "breaching"

  dimensions = local.kinesis_dimensions

  tags = merge(var.tags, {
    AlarmType = "KinesisNoRecords"
    Severity  = "Medium"
  })

  alarm_actions = var.sns_alarm_topic_arn != "" ? [var.sns_alarm_topic_arn] : []
}

# Throttling de escrita - capacidade do stream atingida
resource "aws_cloudwatch_metric_alarm" "kinesis_write_throttled" {
  alarm_name          = "${local.name_prefix}-kinesis-write-throttled"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "WriteProvisionedThroughputExceeded"
  namespace           = "AWS/Kinesis"
  period              = var.alarm_period_seconds
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Alerta: Throttling de escrita detectado no stream"
  treat_missing_data  = "notBreaching"

  dimensions = local.kinesis_dimensions

  tags = merge(var.tags, {
    AlarmType = "KinesisWriteThrottle"
    Severity  = "High"
  })

  alarm_actions = var.sns_alarm_topic_arn != "" ? [var.sns_alarm_topic_arn] : []
}

# Throttling de leitura - consumidores não acompanhando
resource "aws_cloudwatch_metric_alarm" "kinesis_read_throttled" {
  alarm_name          = "${local.name_prefix}-kinesis-read-throttled"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "ReadProvisionedThroughputExceeded"
  namespace           = "AWS/Kinesis"
  period              = var.alarm_period_seconds
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Alerta: Throttling de leitura detectado no stream"
  treat_missing_data  = "notBreaching"

  dimensions = local.kinesis_dimensions

  tags = merge(var.tags, {
    AlarmType = "KinesisReadThrottle"
    Severity  = "High"
  })

  alarm_actions = var.sns_alarm_topic_arn != "" ? [var.sns_alarm_topic_arn] : []
}

# =============================================================================
# ALARMES - KINESIS FIREHOSE (S3)
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "firehose_s3_delivery_failures" {
  count = var.firehose_s3_name != "" ? 1 : 0

  alarm_name          = "${local.name_prefix}-firehose-s3-delivery-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "DeliveryToS3.Failed"
  namespace           = "AWS/Firehose"
  period              = var.alarm_period_seconds
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Alerta: Falhas na entrega de registros para S3"
  treat_missing_data  = "notBreaching"

  dimensions = local.firehose_s3_dimensions

  tags = merge(var.tags, {
    AlarmType = "FirehoseS3Failures"
    Severity  = "High"
  })

  alarm_actions = var.sns_alarm_topic_arn != "" ? [var.sns_alarm_topic_arn] : []
}

resource "aws_cloudwatch_metric_alarm" "firehose_s3_success_rate" {
  count = var.firehose_s3_name != "" ? 1 : 0

  alarm_name          = "${local.name_prefix}-firehose-s3-low-success-rate"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "DeliveryToS3.Success"
  namespace           = "AWS/Firehose"
  period              = var.alarm_period_seconds
  statistic           = "Average"
  threshold           = 100 - var.alarm_thresholds.firehose_delivery_failure_percent
  alarm_description   = "Alerta: Taxa de sucesso na entrega para S3 abaixo de ${100 - var.alarm_thresholds.firehose_delivery_failure_percent}%"
  treat_missing_data  = "notBreaching"

  dimensions = local.firehose_s3_dimensions

  tags = merge(var.tags, {
    AlarmType = "FirehoseS3SuccessRate"
    Severity  = "Medium"
  })

  alarm_actions = var.sns_alarm_topic_arn != "" ? [var.sns_alarm_topic_arn] : []
}

resource "aws_cloudwatch_metric_alarm" "firehose_s3_incoming_records_low" {
  count = var.firehose_s3_name != "" ? 1 : 0

  alarm_name          = "${local.name_prefix}-firehose-s3-no-incoming"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "IncomingRecords"
  namespace           = "AWS/Firehose"
  period              = 600
  statistic           = "Sum"
  threshold           = var.alarm_thresholds.firehose_incoming_records_low
  alarm_description   = "Alerta: Baixo volume de registros entrando no Firehose S3"
  treat_missing_data  = "breaching"

  dimensions = local.firehose_s3_dimensions

  tags = merge(var.tags, {
    AlarmType = "FirehoseS3NoIncoming"
    Severity  = "Medium"
  })

  alarm_actions = var.sns_alarm_topic_arn != "" ? [var.sns_alarm_topic_arn] : []
}

# # =============================================================================
# # ALARMES - KINESIS FIREHOSE (OPENSEARCH)
# # =============================================================================

# resource "aws_cloudwatch_metric_alarm" "firehose_os_delivery_failures" {
#   count = var.firehose_opensearch_name != "" ? 1 : 0

#   alarm_name          = "${local.name_prefix}-firehose-opensearch-delivery-failures"
#   comparison_operator = "GreaterThanThreshold"
#   evaluation_periods  = var.alarm_evaluation_periods
#   metric_name         = "DeliveryToOpenSearch.Failed"
#   namespace           = "AWS/Firehose"
#   period              = var.alarm_period_seconds
#   statistic           = "Sum"
#   threshold           = 0
#   alarm_description   = "Alerta: Falhas na entrega de registros para OpenSearch"
#   treat_missing_data  = "notBreaching"

#   dimensions = local.firehose_opensearch_dimensions

#   tags = merge(var.tags, {
#     AlarmType = "FirehoseOSFailures"
#     Severity  = "High"
#   })

#   alarm_actions = var.sns_alarm_topic_arn != "" ? [var.sns_alarm_topic_arn] : []
# }

# resource "aws_cloudwatch_metric_alarm" "firehose_os_success_rate" {
#   count = var.firehose_opensearch_name != "" ? 1 : 0

#   alarm_name          = "${local.name_prefix}-firehose-opensearch-low-success-rate"
#   comparison_operator = "LessThanThreshold"
#   evaluation_periods  = var.alarm_evaluation_periods
#   metric_name         = "DeliveryToOpenSearch.Success"
#   namespace           = "AWS/Firehose"
#   period              = var.alarm_period_seconds
#   statistic           = "Average"
#   threshold           = 100 - var.alarm_thresholds.firehose_delivery_failure_percent
#   alarm_description   = "Alerta: Taxa de sucesso na entrega para OpenSearch abaixo de ${100 - var.alarm_thresholds.firehose_delivery_failure_percent}%"
#   treat_missing_data  = "notBreaching"

#   dimensions = local.firehose_opensearch_dimensions

#   tags = merge(var.tags, {
#     AlarmType = "FirehoseOSSuccessRate"
#     Severity  = "Medium"
#   })

#   alarm_actions = var.sns_alarm_topic_arn != "" ? [var.sns_alarm_topic_arn] : []
# }

# resource "aws_cloudwatch_metric_alarm" "firehose_os_documents_dropped" {
#   count = var.firehose_opensearch_name != "" ? 1 : 0

#   alarm_name          = "${local.name_prefix}-firehose-opensearch-documents-dropped"
#   comparison_operator = "GreaterThanThreshold"
#   evaluation_periods  = var.alarm_evaluation_periods
#   metric_name         = "Documents.Dropped"
#   namespace           = "AWS/Firehose"
#   period              = var.alarm_period_seconds
#   statistic           = "Sum"
#   threshold           = 0
#   alarm_description   = "Alerta: Documentos sendo descartados pelo Firehose OpenSearch"
#   treat_missing_data  = "notBreaching"

#   dimensions = local.firehose_opensearch_dimensions

#   tags = merge(var.tags, {
#     AlarmType = "FirehoseOSDocumentsDropped"
#     Severity  = "High"
#   })

#   alarm_actions = var.sns_alarm_topic_arn != "" ? [var.sns_alarm_topic_arn] : []
# }

# =============================================================================
# ALARMES - LAMBDA FUNCTIONS
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = { for f in var.lambda_functions : f.name => f }

  alarm_name          = "${local.name_prefix}-lambda-${each.key}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = var.alarm_period_seconds
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Alerta: Erros detectados na função Lambda ${each.key}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.key
  }

  tags = merge(var.tags, {
    AlarmType  = "LambdaErrors"
    Severity   = "High"
    LambdaName = each.key
  })

  alarm_actions = var.sns_alarm_topic_arn != "" ? [var.sns_alarm_topic_arn] : []
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  for_each = { for f in var.lambda_functions : f.name => f }

  alarm_name          = "${local.name_prefix}-lambda-${each.key}-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = var.alarm_period_seconds
  statistic           = "Sum"
  threshold           = var.alarm_thresholds.lambda_throttle_count
  alarm_description   = "Alerta: Throttling detectado na função Lambda ${each.key}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.key
  }

  tags = merge(var.tags, {
    AlarmType  = "LambdaThrottles"
    Severity   = "Medium"
    LambdaName = each.key
  })

  alarm_actions = var.sns_alarm_topic_arn != "" ? [var.sns_alarm_topic_arn] : []
}

# modules/cloudwatch_monitoring/main.tf - Linha ~316

resource "aws_cloudwatch_metric_alarm" "lambda_duration_p95" {
  for_each = { for f in var.lambda_functions : f.name => f }

  alarm_name          = "${local.name_prefix}-lambda-${each.key}-high-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = var.alarm_period_seconds
  statistic           = "Maximum"

  threshold          = var.alarm_thresholds.lambda_duration_p95_ms
  alarm_description  = "Alerta: Duração máxima acima de ${var.alarm_thresholds.lambda_duration_p95_ms}ms na Lambda ${each.key}"
  treat_missing_data = "notBreaching"

  dimensions = {
    FunctionName = each.key
  }

  tags = merge(var.tags, {
    AlarmType  = "LambdaDuration"
    Severity   = "Medium"
    LambdaName = each.key
  })

  alarm_actions = var.sns_alarm_topic_arn != "" ? [var.sns_alarm_topic_arn] : []
}

# =============================================================================
# ALARMES - OPENSEARCH SERVERLESS (AWS/AOSS)
# =============================================================================

# resource "aws_cloudwatch_metric_alarm" "opensearch_serverless_search_ocu" {
#   count = var.opensearch_type == "serverless" && var.opensearch_collection_name != "" ? 1 : 0

#   alarm_name          = "${local.name_prefix}-opensearch-serverless-high-search-ocu"
#   comparison_operator = "GreaterThanThreshold"
#   evaluation_periods  = var.alarm_evaluation_periods
#   metric_name         = "SearchOCUUtilization"
#   namespace           = "AWS/AOSS"  # ✅ Serverless usa AWS/AOSS
#   period              = var.alarm_period_seconds
#   statistic           = "Average"
#   threshold           = var.alarm_thresholds.opensearch_ocu_utilization
#   alarm_description   = "Alerta: Utilização de Search OCU acima de ${var.alarm_thresholds.opensearch_ocu_utilization}%"
#   treat_missing_data  = "notBreaching"

#   dimensions = {
#     CollectionName = var.opensearch_collection_name
#   }

#   tags = merge(var.tags, {
#     AlarmType = "OpenSearchServerlessSearchOCU"
#     Severity  = "High"
#   })

#   alarm_actions = var.sns_alarm_topic_arn != "" ? [var.sns_alarm_topic_arn] : []
# }

# resource "aws_cloudwatch_metric_alarm" "opensearch_serverless_indexing_ocu" {
#   count = var.opensearch_type == "serverless" && var.opensearch_collection_name != "" ? 1 : 0

#   alarm_name          = "${local.name_prefix}-opensearch-serverless-high-indexing-ocu"
#   comparison_operator = "GreaterThanThreshold"
#   evaluation_periods  = var.alarm_evaluation_periods
#   metric_name         = "IndexingOCUUtilization"
#   namespace           = "AWS/AOSS"
#   period              = var.alarm_period_seconds
#   statistic           = "Average"
#   threshold           = var.alarm_thresholds.opensearch_ocu_utilization
#   alarm_description   = "Alerta: Utilização de Indexing OCU acima de ${var.alarm_thresholds.opensearch_ocu_utilization}%"
#   treat_missing_data  = "notBreaching"

#   dimensions = {
#     CollectionName = var.opensearch_collection_name
#   }

#   tags = merge(var.tags, {
#     AlarmType = "OpenSearchServerlessIndexingOCU"
#     Severity  = "High"
#   })

#   alarm_actions = var.sns_alarm_topic_arn != "" ? [var.sns_alarm_topic_arn] : []
# }

# resource "aws_cloudwatch_metric_alarm" "opensearch_serverless_indexing_failures" {
#   count = var.opensearch_type == "serverless" && var.opensearch_collection_name != "" ? 1 : 0

#   alarm_name          = "${local.name_prefix}-opensearch-serverless-indexing-failures"
#   comparison_operator = "GreaterThanThreshold"
#   evaluation_periods  = var.alarm_evaluation_periods
#   metric_name         = "IndexingFailures"
#   namespace           = "AWS/AOSS"
#   period              = var.alarm_period_seconds
#   statistic           = "Sum"
#   threshold           = var.alarm_thresholds.opensearch_indexing_failures
#   alarm_description   = "Alerta: Falhas de indexação no OpenSearch Serverless"
#   treat_missing_data  = "notBreaching"

#   dimensions = {
#     CollectionName = var.opensearch_collection_name
#   }

#   tags = merge(var.tags, {
#     AlarmType = "OpenSearchServerlessIndexing"
#     Severity  = "High"
#   })

#   alarm_actions = var.sns_alarm_topic_arn != "" ? [var.sns_alarm_topic_arn] : []
# }

# =============================================================================
# MAINTENANCE WINDOW ALARM (para actions_suppressor)
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "maintenance_window" {
  alarm_name          = "${local.name_prefix}-maintenance-window"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "MaintenanceMode"
  namespace           = "Custom/FlightRadar"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1
  alarm_description   = "Alarme para suprimir notificações durante janela de manutenção"
  treat_missing_data  = "notBreaching"

  tags = merge(var.tags, {
    AlarmType = "MaintenanceWindow"
    Severity  = "Info"
  })
}

# =============================================================================
# COMPOSITE ALARM - Com actions_suppressor
# =============================================================================

resource "aws_cloudwatch_composite_alarm" "pipeline_critical" {
  alarm_name        = "${local.name_prefix}-pipeline-critical"
  alarm_description = "Alarme composto: Qualquer falha crítica no pipeline de streaming"

  alarm_rule = join(" OR ", compact([
    var.kinesis_stream_name != "" ? "ALARM(\"${aws_cloudwatch_metric_alarm.kinesis_iterator_age.alarm_name}\")" : null,
    var.kinesis_stream_name != "" ? "ALARM(\"${aws_cloudwatch_metric_alarm.kinesis_write_throttled.alarm_name}\")" : null,
    var.firehose_s3_name != "" ? "ALARM(\"${aws_cloudwatch_metric_alarm.firehose_s3_delivery_failures[0].alarm_name}\")" : null,
    # var.firehose_opensearch_name != "" ? "ALARM(\"${aws_cloudwatch_metric_alarm.firehose_os_delivery_failures[0].alarm_name}\")" : null,
    # var.opensearch_type == "serverless" && var.opensearch_collection_name != "" ? "ALARM(\"${aws_cloudwatch_metric_alarm.opensearch_serverless_indexing_failures[0].alarm_name}\")" : null,
  ]))

  tags = merge(var.tags, {
    AlarmType = "CompositeCritical"
    Severity  = "Critical"
  })

  actions_suppressor {
    alarm            = aws_cloudwatch_metric_alarm.maintenance_window.alarm_name
    wait_period      = 300
    extension_period = 600
  }

  depends_on = [
    aws_cloudwatch_metric_alarm.maintenance_window
  ]
}

resource "aws_cloudwatch_composite_alarm" "pipeline_degraded" {
  alarm_name        = "${local.name_prefix}-pipeline-degraded"
  alarm_description = "Alarme composto: Pipeline operando com degradação"

  alarm_rule = join(" OR ", compact([
    var.kinesis_stream_name != "" ? "ALARM(\"${aws_cloudwatch_metric_alarm.kinesis_read_throttled.alarm_name}\")" : null,
    var.firehose_s3_name != "" ? "ALARM(\"${aws_cloudwatch_metric_alarm.firehose_s3_success_rate[0].alarm_name}\")" : null,
    # var.firehose_opensearch_name != "" ? "ALARM(\"${aws_cloudwatch_metric_alarm.firehose_os_success_rate[0].alarm_name}\")" : null,
    # var.opensearch_type == "serverless" && var.opensearch_collection_name != "" ? "ALARM(\"${aws_cloudwatch_metric_alarm.opensearch_serverless_search_ocu[0].alarm_name}\")" : null,
    length(var.lambda_functions) > 0 ? "ALARM(\"${aws_cloudwatch_metric_alarm.lambda_errors[var.lambda_functions[0].name].alarm_name}\")" : null,
  ]))

  tags = merge(var.tags, {
    AlarmType = "CompositeDegraded"
    Severity  = "Warning"
  })
}

# =============================================================================
# CLOUDWATCH DASHBOARD - Unificação de Métricas
# =============================================================================

resource "aws_cloudwatch_dashboard" "streaming_pipeline" {
  dashboard_name = "${local.name_prefix}-streaming-pipeline"

  dashboard_body = jsonencode({
    widgets = local.dashboard_widgets
  })
}

# =============================================================================
# SNS TOPIC PARA NOTIFICAÇÕES
# =============================================================================
resource "aws_sns_topic" "pipeline_alarms" {
  name = "${var.project_name}-${var.environment}-pipeline-alarms"

  tags = merge(var.tags, {
    Purpose = "CloudWatch Alarms"
  })
}

# Subscription para email
resource "aws_sns_topic_subscription" "alerts_email" {
  count = length(var.alerts_email) > 0 ? 1 : 0

  topic_arn = aws_sns_topic.pipeline_alarms.arn
  protocol  = "email"
  endpoint  = var.alerts_email[count.index]
}
