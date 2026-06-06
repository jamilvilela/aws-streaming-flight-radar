# Data source para obter informações do stream (usa o primeiro stream do map para compatibilidade)
data "aws_kinesis_stream" "stream_info" {
  name       = values(aws_kinesis_stream.this)[0].name
  depends_on = [aws_kinesis_stream.this]
}