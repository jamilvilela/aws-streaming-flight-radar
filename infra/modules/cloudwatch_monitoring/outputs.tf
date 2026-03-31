output "dashboard_name" {
  description = "Nome do dashboard CloudWatch"
  value       = aws_cloudwatch_dashboard.streaming_pipeline.dashboard_name
}

output "dashboard_arn" {
  description = "ARN do dashboard CloudWatch"
  value       = aws_cloudwatch_dashboard.streaming_pipeline.dashboard_arn
}

output "sns_topic_arn" {
  description = "ARN do tópico SNS para alarmes"
  value       = aws_sns_topic.pipeline_alarms.arn
}

output "critical_composite_alarm_arn" {
  description = "ARN do alarme composto crítico"
  value       = aws_cloudwatch_composite_alarm.pipeline_critical.arn
}

output "degraded_composite_alarm_arn" {
  description = "ARN do alarme composto de degradação"
  value       = aws_cloudwatch_composite_alarm.pipeline_degraded.arn
}

# OpenSearch Serverless Alarms
output "opensearch_serverless_alarms" {
  description = "Mapa com ARNs dos alarmes do OpenSearch Serverless"
  value = var.opensearch_type == "serverless" ? {
    search_ocu      = try(aws_cloudwatch_metric_alarm.opensearch_serverless_search_ocu[0].arn, null)
    indexing_ocu    = try(aws_cloudwatch_metric_alarm.opensearch_serverless_indexing_ocu[0].arn, null)
    indexing_errors = try(aws_cloudwatch_metric_alarm.opensearch_serverless_indexing_failures[0].arn, null)
  } : {}
}


output "kinesis_alarms" {
  description = "Mapa com ARNs dos alarmes do Kinesis"
  value = {
    iterator_age      = aws_cloudwatch_metric_alarm.kinesis_iterator_age.arn
    no_records        = aws_cloudwatch_metric_alarm.kinesis_no_incoming_records.arn
    write_throttled   = aws_cloudwatch_metric_alarm.kinesis_write_throttled.arn
    read_throttled    = aws_cloudwatch_metric_alarm.kinesis_read_throttled.arn
  }
}

output "firehose_s3_alarms" {
  description = "Mapa com ARNs dos alarmes do Firehose S3"
  value = var.firehose_s3_name != "" ? {
    delivery_failures = aws_cloudwatch_metric_alarm.firehose_s3_delivery_failures[0].arn
    success_rate      = aws_cloudwatch_metric_alarm.firehose_s3_success_rate[0].arn
    incoming_low      = aws_cloudwatch_metric_alarm.firehose_s3_incoming_records_low[0].arn
  } : {}
}

output "firehose_opensearch_alarms" {
  description = "Mapa com ARNs dos alarmes do Firehose OpenSearch"
  value = var.firehose_opensearch_name != "" ? {
    delivery_failures  = aws_cloudwatch_metric_alarm.firehose_os_delivery_failures[0].arn
    success_rate       = aws_cloudwatch_metric_alarm.firehose_os_success_rate[0].arn
    documents_dropped  = aws_cloudwatch_metric_alarm.firehose_os_documents_dropped[0].arn
  } : {}
}

output "lambda_alarms" {
  description = "Mapa com ARNs dos alarmes das Lambdas"
  value = {
    for f in var.lambda_functions : f.name => {
      errors    = aws_cloudwatch_metric_alarm.lambda_errors[f.name].arn
      throttles = aws_cloudwatch_metric_alarm.lambda_throttles[f.name].arn
      duration  = aws_cloudwatch_metric_alarm.lambda_duration_p95[f.name].arn
    }
  }
}

output "aws_sns_topic_pipeline_alarms_arn" {
  value = aws_sns_topic.pipeline_alarms.arn
  description = "ARN do tópico SNS para alarmes do pipeline de streaming"  
}