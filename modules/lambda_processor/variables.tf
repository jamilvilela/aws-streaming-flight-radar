variable "lambda_function_name" { 
    type = string 
}
variable "role_arn" { 
    type = string 
}
variable "handler" { 
    type = string 
}
variable "runtime" { 
    type = string 
}
variable "lambda_file_name" { 
    type = string 
}
variable "environment_variables" { 
    type = map(string) 
    default = {} 
}
variable "subnet_ids" { 
    type = list(string) 
}
variable "security_group_ids" { 
    type = list(string) 
}
variable "kinesis_stream_arn" { 
    type = string 
}
variable "tags" { 
    type = map(string) 
    default = {} 
}