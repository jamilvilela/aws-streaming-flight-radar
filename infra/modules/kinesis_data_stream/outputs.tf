output "kinesis_stream_arns" {
  description = "ARNs dos streams Kinesis criados"
  value = {
    for name, stream in aws_kinesis_stream.kinesis_stream :
    name => stream.arn
  }
}

output "kinesis_stream_names" {
  description = "Nomes dos streams Kinesis criados"
  value = {
    for name, stream in aws_kinesis_stream.kinesis_stream :
    name => stream.name
  }
}

output "kinesis_streams_info" {
  description = "Informações completas dos streams Kinesis"
  value = {
    for key, stream in aws_kinesis_stream.kinesis_stream :
    key => {
      name              = stream.name
      arn               = stream.arn
      retention_hours   = stream.retention_period
      mode              = stream.stream_mode_details != null ? stream.stream_mode_details[0].stream_mode : "PROVISIONED"
      shard_count       = stream.shard_count
    }
  }
}

output "kinesis_stream_endpoints" {
  description = "Endpoints dos streams para conexão"
  value = {
    for key, stream in aws_kinesis_stream.kinesis_stream :
    key => {
      stream_name = stream.name
      # Lambda enviará dados usando PutRecord/PutRecords
      put_record_endpoint = "kinesis.${stream.arn}"
    }
  }
}