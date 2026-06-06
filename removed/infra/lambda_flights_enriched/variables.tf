variable "lambda_config" {
    description = "Configuration for the Lambda function"
    type        = object({
        name                          = string
        handler                       = string
        runtime                       = string
        timeout                       = number
        memory_size                   = number
        ephemeral_storage             = number
        tags                          = map(string)
    })  
}
variable "project_name" { type = string }
variable "aws_region" { type = string }
variable "role_arn" { type = string }
variable "kinesis_firehose" { 
    type = object(
        {
            name              = string
            prefix             = string
            error_output_prefix = string
        })
}
variable "tags" { 
    type = map(string) 
    default = {} 
}