resource "aws_kinesis_firehose_delivery_stream" "firehose_flights_to_s3" {
  name        = var.kinesis_firehose.name
  destination = "extended_s3"
 
  kinesis_source_configuration {
    kinesis_stream_arn = var.kinesis_stream_arn
    role_arn           = var.role_arn
  }

  extended_s3_configuration {
    role_arn            = var.role_arn 
    bucket_arn          = var.bucket_arn
    compression_format  = "Snappy"
    file_extension      = ".json"
    custom_time_zone    = "America/Sao_Paulo"
    buffering_interval  = 60
    buffering_size      = 2

    dynamic_partitioning_configuration {
      enabled = false
    }

    prefix              = "opensky/flights/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"
    error_output_prefix = "opensky/flights-errors/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/!{firehose:error-output-type}/"
    # prefix              = "opensky/flights/"
    # error_output_prefix = "opensky/flights-errors/"


    cloudwatch_logging_options {
      enabled         = "true"
      log_group_name  = "/aws/kinesisfirehose/${var.kinesis_firehose.name}"
      log_stream_name = "S3Delivery"
    }

    s3_backup_mode = "Disabled"
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

  #   processing_configuration {
  #     enabled = true
  #     processors {
  #       type = "Lambda"
  #       parameters {
  #         parameter_name  = "LambdaArn"
  #         parameter_value = var.lambda_arn
  #       }
  #     }
  #   }
 