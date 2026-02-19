resource "aws_kinesis_stream" "kinesis_stream_flights_raw" {
  name             = var.kinesis_stream.name
  retention_period = var.retention_hours

  stream_mode_details {
    stream_mode = var.kinesis_stream.mode  
  }

  tags = merge(
    var.tags,
    {
      Name        = var.kinesis_stream.name
      StreamType  = "fights-raw"
      Environment = var.environment
    }
  )
}

resource "aws_cloudwatch_metric_alarm" "kinesis_iterator_age" {
  alarm_name          = "${aws_kinesis_stream.kinesis_stream_flights_raw.name}-high-iterator-age"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "GetRecords.IteratorAgeMilliseconds"
  namespace           = "AWS/Kinesis"
  period              = 300  # 5 minutos
  statistic           = "Maximum"
  threshold           = 60000  # 60 segundos
  alarm_description   = "Alert quando registros não são processados por mais de 60 segundos"
  dimensions = {
    StreamName = aws_kinesis_stream.kinesis_stream_flights_raw.name
  }
}

resource "aws_cloudwatch_metric_alarm" "kinesis_incoming_records" {
   alarm_name          = "${aws_kinesis_stream.kinesis_stream_flights_raw.name}-no-incoming-records"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "IncomingRecords"
  namespace           = "AWS/Kinesis"
  period              = 600
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Alert quando nenhum registro entra no stream por 10+ minutos"
  dimensions = {
    StreamName = aws_kinesis_stream.kinesis_stream_flights_raw.name
  }
}

