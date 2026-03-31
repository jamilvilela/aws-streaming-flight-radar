
output "kinesis_firehose_to_opensearch_arn" {
  description = "ARN do Kinesis Firehose criado"
  value = aws_kinesis_firehose_delivery_stream.flights_to_opensearch.arn
}

output "kinesis_firehose_to_opensearch_name" {
  description = "Nome do Kinesis Firehose criado"
  value = aws_kinesis_firehose_delivery_stream.flights_to_opensearch.name
}

output "kinesis_firehose_to_opensearch_info" {
  description = "Informações completas do Kinesis Firehose"
  value = {
    name = aws_kinesis_firehose_delivery_stream.flights_to_opensearch.name
    arn = aws_kinesis_firehose_delivery_stream.flights_to_opensearch.arn
  }
}