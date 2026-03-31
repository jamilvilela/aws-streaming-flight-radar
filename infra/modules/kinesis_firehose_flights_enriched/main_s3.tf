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
    
    prefix              = "opensky/enriched-flights/"
    error_output_prefix = "opensky/enriched-flights-errors/"
    
    kms_key_arn         = var.kms_firehose_arn
    buffering_interval  = 60
    buffering_size      = 2

    dynamic_partitioning_configuration {
      enabled = false
    }

    cloudwatch_logging_options {
      enabled         = true
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
 