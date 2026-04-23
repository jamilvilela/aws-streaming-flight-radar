
output "kinesis_stream_flight_arn" {
  description = "ARN do stream Kinesis para dados brutos"
  value = aws_kinesis_stream.kinesis_stream_flights.arn
}

output "kinesis_stream_name" {
  description = "Nome do stream Kinesis para dados brutos"
  value = aws_kinesis_stream.kinesis_stream_flights.name
}

output "kinesis_stream_flights_rt_arn" {
  description = "ARN do Kinesis Stream para dados em tempo real (Redshift)"
  value       = aws_kinesis_stream.kinesis_stream_flights_rt.arn
}

output "kinesis_stream_flights_rt_name" {
  description = "Nome do Kinesis Stream para dados em tempo real (Redshift)"
  value       = aws_kinesis_stream.kinesis_stream_flights_rt.name
}

output "kinesis_streams_info" {
  description = "Informações completas do stream Kinesis"
  value = {
    name              = aws_kinesis_stream.kinesis_stream_flights.name
    arn               = aws_kinesis_stream.kinesis_stream_flights.arn
    retention_hours   = aws_kinesis_stream.kinesis_stream_flights.retention_period
    mode              = aws_kinesis_stream.kinesis_stream_flights.stream_mode_details != null ? aws_kinesis_stream.kinesis_stream_flights.stream_mode_details[0].stream_mode : "ON_DEMAND"
  }
}

output "kinesis_stream_flights_endpoints" {
  description = "Endpoint do stream para conexão"
  value = {
    stream_name = aws_kinesis_stream.kinesis_stream_flights.name
    # Lambda enviará dados usando PutRecord/PutRecords
    put_record_endpoint = "kinesis.${aws_kinesis_stream.kinesis_stream_flights.arn}"
  }
}