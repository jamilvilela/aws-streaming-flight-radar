resource "aws_kinesis_firehose_delivery_stream" "kinesis_firehose_flights_enriched" {
  name        = var.kinesis_firehose.name
  destination = "extended_s3"
 
  kinesis_source_configuration {
    kinesis_stream_arn = var.kinesis_stream_arn
    role_arn           = var.role_arn
  }
  
  extended_s3_configuration {
    role_arn            = var.role_arn
    bucket_arn          = var.bucket_arn
    prefix              = "opensky/enriched-flights/"
    error_output_prefix = "opensky/enriched-flights-errors/"

    processing_configuration {
      enabled = true
      processors {
        type = "Lambda"
        parameters {
          parameter_name  = "LambdaArn"
          parameter_value = var.lambda_arn
        }
      }
    }
  }

  tags = merge(
    var.tags,
    {
      Name        = var.kinesis_firehose.name
      StreamType  = "flights-enriched"
      Environment = var.environment
    }
  )
}

resource "aws_cloudwatch_metric_alarm" "kinesis_iterator_age" {
  alarm_name          = "${var.kinesis_firehose.name}-high-iterator-age"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "GetRecords.IteratorAgeMilliseconds"
  namespace           = "AWS/Kinesis"
  period              = 300  # 5 minutos
  statistic           = "Maximum"
  threshold           = 60000  # 60 segundos
  alarm_description   = "Alert quando registros não são processados por mais de 60 segundos"
  dimensions = {
    StreamName = aws_kinesis_firehose_delivery_stream.kinesis_firehose_flights_enriched.name
  }
}

resource "aws_cloudwatch_metric_alarm" "kinesis_incoming_records" {
  alarm_name          = "${var.kinesis_firehose.name}-no-incoming-records"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "IncomingRecords"
  namespace           = "AWS/Kinesis"
  period              = 600
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Alert quando nenhum registro entra no stream por 10+ minutos"
  dimensions = {
    StreamName = aws_kinesis_firehose_delivery_stream.kinesis_firehose_flights_enriched.name
  }
}