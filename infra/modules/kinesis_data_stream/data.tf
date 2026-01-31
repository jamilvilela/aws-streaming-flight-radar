# Data source para obter informações do stream
data "aws_kinesis_stream" "stream_info" {
  for_each = aws_kinesis_stream.kinesis_stream
  
  name = each.value.name

  depends_on = [aws_kinesis_stream.kinesis_stream]
}