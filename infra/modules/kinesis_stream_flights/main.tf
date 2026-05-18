# ============================================================================
# KINESIS STREAMS - CRIAÇÃO DINÂMICA
# ============================================================================
# Cria múltiplos streams Kinesis a partir do map kinesis_streams
# Cada stream pode ser: flights, flights_rt, outputs de Flink, etc.

resource "aws_kinesis_stream" "this" {
  for_each          = var.kinesis_streams
  name             = each.value.name
  retention_period = var.retention_hours

  stream_mode_details {
    stream_mode = each.value.mode
  }

  tags = merge(
    var.tags,
    {
      Name        = each.value.name
      Environment = var.environment
    }
  )
}

