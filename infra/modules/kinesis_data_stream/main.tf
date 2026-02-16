resource "aws_kinesis_stream" "kinesis_stream" {
  for_each = var.kinesis_streams
  
  name            = each.value.stream_name
  retention_period = var.retention_hours  


  stream_mode_details {
    stream_mode = "ON_DEMAND"  
  }

  tags = merge(
    var.tags,
    {
      Name        = each.value.stream_name
      StreamType  = each.key
      Environment = var.environment
    }
  )
}

resource "aws_cloudwatch_metric_alarm" "kinesis_iterator_age" {
  for_each = var.kinesis_streams

  alarm_name          = "${each.value.stream_name}-high-iterator-age"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "GetRecords.IteratorAgeMilliseconds"
  namespace           = "AWS/Kinesis"
  period              = 300  # 5 minutos
  statistic           = "Maximum"
  threshold           = 60000  # 60 segundos
  alarm_description   = "Alert quando registros não são processados por mais de 60 segundos"
  dimensions = {
    StreamName = aws_kinesis_stream.kinesis_stream[each.key].name
  }
}

resource "aws_cloudwatch_metric_alarm" "kinesis_incoming_records" {
  for_each = var.kinesis_streams

  alarm_name          = "${each.value.stream_name}-no-incoming-records"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "IncomingRecords"
  namespace           = "AWS/Kinesis"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Alert quando nenhum registro entra no stream por 5+ minutos"
  dimensions = {
    StreamName = aws_kinesis_stream.kinesis_stream[each.key].name
  }
}

