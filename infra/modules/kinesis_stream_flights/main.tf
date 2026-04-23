# ETAPA 2A: STREAMING EM TEMPO REAL - FLUXO PRINCIPAL (RAW)
# Kinesis Stream para receber dados brutos de voos da OpenSky API
# Alimenta:
#   1. Kinesis Firehose → S3 Landing (armazenamento bruto)
#   2. Flink (KDA) para processamento em tempo real
#
# Estrutura do fluxo:
# OpenSky API → Lambda-ingestão → kinesis_stream_flights → Firehose + Flink
resource "aws_kinesis_stream" "kinesis_stream_flights" {
  name             = var.kinesis_stream.name
  retention_period = var.retention_hours

  stream_mode_details {
    stream_mode = var.kinesis_stream.mode  
  }

  tags = merge(
    var.tags,
    {
      Name        = var.kinesis_stream.name
      StreamType  = "flights-raw"
      Environment = var.environment
    }
  )
}

# ETAPA 2B: STREAMING EM TEMPO REAL - FLUXO ENRIQUECIDO (REDSHIFT)
# Kinesis Stream para receber dados enriquecidos processados pelo Flink
# Alimenta:
#   1. Redshift Warehouse (data warehouse em tempo real)
#   2. QuickSight para dashboards BI
#
# Estrutura do fluxo:
# kinesis_stream_flights → Flink (KDA) → kinesis_stream_flights_rt → Redshift → QuickSight
resource "aws_kinesis_stream" "kinesis_stream_flights_rt" {
  name             = "${var.kinesis_stream.name}-rt"
  retention_period = var.retention_hours

  stream_mode_details {
    stream_mode = var.kinesis_stream.mode  
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.kinesis_stream.name}-rt" 
      StreamType  = "flights-redshift-rt"
      Environment = var.environment
    }
  )
}

