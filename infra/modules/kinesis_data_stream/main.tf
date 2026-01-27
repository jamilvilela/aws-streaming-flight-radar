resource "aws_kinesis_stream" "kinesis-stream" {
  for_each = var.kinesis_streams
  
  name        = "kinesis-data-stream-${each.key}"
  shard_count = each.value.shard_count
  retention_period = 24  # Período de retenção de 24 horas

  stream_mode_details {
    stream_mode = "PROVISIONED"  # Modo provisionado para controle preciso
  }

  tags = merge(
    var.tags,
    {
      Name   = "kinesis-data-stream-${each.key}"
    }
  )
}

output "kinesis_stream_arns" {
  description = "ARNs dos streams Kinesis criados."
  value = {
    for name, stream in aws_kinesis_stream.kinesis-stream :
    name => stream.arn
  }
}

output "kinesis_stream_names" {
  description = "Nomes dos streams Kinesis criados."
  value = {
    for name, stream in aws_kinesis_stream.kinesis-stream :
    name => stream.name
  }
}