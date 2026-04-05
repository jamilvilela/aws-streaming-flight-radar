resource "aws_kinesis_firehose_delivery_stream" "flights_to_opensearch" {
  name        = "flight-radar-firehose-opensearch"
  destination = "opensearchserverless"  

  kinesis_source_configuration {
    kinesis_stream_arn = var.kinesis_stream_arn
    role_arn           = var.role_arn
  }

  opensearchserverless_configuration {  
    role_arn            = var.role_arn
    collection_endpoint = var.opensearch_collection_endpoint
    index_name          = var.opensearch_index_name
    
    buffering_interval = 60
    buffering_size     = 2
    retry_duration     = 300
    
    s3_backup_mode = "FailedDocumentsOnly"    
    s3_configuration {
      role_arn   = var.role_arn
      bucket_arn = var.bucket_arn
      prefix     = "opensky/opensearch-flights-backup/"
    }

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = "/aws/kinesisfirehose/flights-opensearch-serverless"
      log_stream_name = "Delivery"
    }
  }

  tags = merge(var.tags, {
    Name        = "flight-radar-firehose-opensearch-serverless"
    StreamType  = "flights-to-opensearch-serverless"
    Environment = var.environment
  })
}
