locals {
  access_log_format = jsonencode({
    requestId        = "$context.requestId"
    ip               = "$context.identity.sourceIp"
    caller           = "$context.identity.caller"
    user             = "$context.identity.user"
    requestTime      = "$context.requestTime"
    httpMethod       = "$context.httpMethod"
    resourcePath     = "$context.resourcePath"
    status           = "$context.status"
    protocol         = "$context.protocol"
    responseLength   = "$context.responseLength"
    integrationError = "$context.integrationErrorMessage"
  })
}
