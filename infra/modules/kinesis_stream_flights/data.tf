# Data source para obter informações do stream
data "aws_kinesis_stream" "stream_info" {
  name = aws_kinesis_stream.kinesis_stream_flights.name
  depends_on = [aws_kinesis_stream.kinesis_stream_flights]
}