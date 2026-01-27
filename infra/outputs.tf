

output "kinesis_stream_arns" {
  description = "ARNs dos streams Kinesis criados."
  value = {
    for name, stream in module.aws_kinesis_stream.kinesis-stream :
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