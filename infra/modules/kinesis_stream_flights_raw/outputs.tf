
output "kinesis_stream_flight_raw_arn" {
  description = "ARN dos stream Kinesis criado"
  value = aws_kinesis_stream.kinesis_stream_flights_raw.arn
}

output "kinesis_stream_name" {
  description = "Nome do stream Kinesis criado"
  value = aws_kinesis_stream.kinesis_stream_flights_raw.name
}

output "kinesis_streams_info" {
  description = "Informações completas do stream Kinesis"
  value = {
    name              = aws_kinesis_stream.kinesis_stream_flights_raw.name
    arn               = aws_kinesis_stream.kinesis_stream_flights_raw.arn
    retention_hours   = aws_kinesis_stream.kinesis_stream_flights_raw.retention_period
    mode              = aws_kinesis_stream.kinesis_stream_flights_raw.stream_mode_details != null ? aws_kinesis_stream.kinesis_stream_flights_raw.stream_mode_details[0].stream_mode : "ON_DEMAND"
  }
}

output "kinesis_stream_flights_raw_endpoints" {
  description = "Endpoint do stream para conexão"
  value = {
    stream_name = aws_kinesis_stream.kinesis_stream_flights_raw.name
    # Lambda enviará dados usando PutRecord/PutRecords
    put_record_endpoint = "kinesis.${aws_kinesis_stream.kinesis_stream_flights_raw.arn}"
  }
}