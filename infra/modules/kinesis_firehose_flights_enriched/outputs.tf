
output "kinesis_firehose_flights_enriched_arn" {
  description = "ARN do Kinesis Firehose criado"
  value = aws_kinesis_firehose_delivery_stream.kinesis_firehose_flights_enriched.arn
}

output "kinesis_firehose_flights_enriched_name" {
  description = "Nome do Kinesis Firehose criado"
  value = aws_kinesis_firehose_delivery_stream.kinesis_firehose_flights_enriched.name
}

output "kinesis_firehose_flights_enriched_info" {
  description = "Informações completas do Kinesis Firehose"
  value = {
    name = aws_kinesis_firehose_delivery_stream.kinesis_firehose_flights_enriched.name
    arn = aws_kinesis_firehose_delivery_stream.kinesis_firehose_flights_enriched.arn
  }
}