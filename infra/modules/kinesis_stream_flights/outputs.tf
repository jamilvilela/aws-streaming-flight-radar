# ARNs dos streams - map completo
output "streams_arn" {
  description = "Map de ARNs de todos os streams Kinesis"
  value       = { for k, v in aws_kinesis_stream.this : k => v.arn }
}

# Nomes dos streams - map completo
output "streams_name" {
  description = "Map de nomes de todos os streams Kinesis"
  value       = { for k, v in aws_kinesis_stream.this : k => v.name }
}

# Output para backward compatibility - flights (input)
output "kinesis_stream_flight_arn" {
  description = "ARN do stream Kinesis para dados brutos (flights)"
  value       = try(aws_kinesis_stream.this["flights"].arn, null)
}

output "kinesis_stream_name" {
  description = "Nome do stream Kinesis para dados brutos (flights)"
  value       = try(aws_kinesis_stream.this["flights"].name, null)
}

# Output para backward compatibility - flights_rt (output)
output "kinesis_stream_flights_rt_arn" {
  description = "ARN do Kinesis Stream para dados em tempo real (flights_rt)"
  value       = try(aws_kinesis_stream.this["flights_rt"].arn, null)
}

output "kinesis_stream_flights_rt_name" {
  description = "Nome do Kinesis Stream para dados em tempo real (flights_rt)"
  value       = try(aws_kinesis_stream.this["flights_rt"].name, null)
}

# Informações completas dos streams
output "kinesis_streams_info" {
  description = "Informações completas de todos os streams Kinesis"
  value = {
    for k, v in aws_kinesis_stream.this :
    k => {
      name            = v.name
      arn             = v.arn
      retention_hours = v.retention_period
      mode            = v.stream_mode_details[0].stream_mode
    }
  }
}

output "all_stream_arns" {
  description = "Lista de todos os ARNs dos streams"
  value       = values(aws_kinesis_stream.this)[*].arn
}