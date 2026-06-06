resource "aws_api_gateway_rest_api" "this" {
  name        = "${var.project_name}-${var.api_name}"
  description = var.api_description

  endpoint_configuration {
    types = [var.endpoint_type] # "REGIONAL" or "EDGE"
  }

  tags = var.tags
}

resource "aws_api_gateway_resource" "flights" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "flights"
}

resource "aws_api_gateway_resource" "flights_batch" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.flights.id
  path_part   = "batch"
}

# ---------------- /flights (single record POST) ----------------
resource "aws_api_gateway_method" "post_flights" {
  rest_api_id      = aws_api_gateway_rest_api.this.id
  resource_id      = aws_api_gateway_resource.flights.id
  http_method      = "POST"
  authorization    = "CUSTOM"
  authorizer_id    = aws_api_gateway_authorizer.this.id
  api_key_required = true
}

resource "aws_api_gateway_integration" "post_flights_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.flights.id
  http_method             = aws_api_gateway_method.post_flights.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arn
}

# ---------------- /flights/batch (multi record POST) ----------------
resource "aws_api_gateway_method" "post_flights_batch" {
  rest_api_id      = aws_api_gateway_rest_api.this.id
  resource_id      = aws_api_gateway_resource.flights_batch.id
  http_method      = "POST"
  authorization    = "CUSTOM"
  authorizer_id    = aws_api_gateway_authorizer.this.id
  api_key_required = true
}

resource "aws_api_gateway_integration" "post_flights_batch_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.flights_batch.id
  http_method             = aws_api_gateway_method.post_flights_batch.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arn
}

# ---------------- /flights (GET - healthcheck shape) ----------------
resource "aws_api_gateway_method" "get_flights" {
  rest_api_id      = aws_api_gateway_rest_api.this.id
  resource_id      = aws_api_gateway_resource.flights.id
  http_method      = "GET"
  authorization    = "CUSTOM"
  authorizer_id    = aws_api_gateway_authorizer.this.id
  api_key_required = true
}

resource "aws_api_gateway_integration" "get_flights_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.flights.id
  http_method             = aws_api_gateway_method.get_flights.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arn
}

# ---------------- Authorizer ----------------
resource "aws_api_gateway_authorizer" "this" {
  name                             = "${var.project_name}-${var.api_name}-authorizer"
  rest_api_id                      = aws_api_gateway_rest_api.this.id
  authorizer_uri                   = var.authorizer_invoke_arn
  authorizer_credentials           = var.authorizer_credentials_arn
  type                             = "TOKEN"
  identity_source                  = "method.request.header.X-Api-Key"
  authorizer_result_ttl_in_seconds = 300
}

# ---------------- Deployment ----------------
resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    redeploy = sha1(jsonencode([
      aws_api_gateway_resource.flights.id,
      aws_api_gateway_resource.flights_batch.id,
      aws_api_gateway_method.post_flights.id,
      aws_api_gateway_method.post_flights_batch.id,
      aws_api_gateway_method.get_flights.id,
      aws_api_gateway_integration.post_flights_lambda.id,
      aws_api_gateway_integration.post_flights_batch_lambda.id,
      aws_api_gateway_integration.get_flights_lambda.id,
      aws_api_gateway_authorizer.this.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "this" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
  stage_name    = var.stage_name

  dynamic "access_log_settings" {
    for_each = var.enable_access_logs ? [1] : []
    content {
      destination_arn = var.access_log_group_arn
      format          = local.access_log_format
    }
  }

  tags = var.tags
}

# ---------------- Usage Plan + API Key ----------------
resource "aws_api_gateway_usage_plan" "this" {
  name        = "${var.project_name}-${var.api_name}-usage-plan"
  description = "Throttling and quota for the ${var.api_name} API"

  api_stages {
    api_id = aws_api_gateway_rest_api.this.id
    stage  = aws_api_gateway_stage.this.stage_name
  }

  throttle_settings {
    burst_limit = var.throttle_burst_limit
    rate_limit  = var.throttle_rate_limit
  }

  quota_settings {
    limit  = var.quota_limit
    period = var.quota_period
  }

  tags = var.tags
}

resource "aws_api_gateway_api_key" "this" {
  count = var.create_api_key ? 1 : 0

  name        = "${var.project_name}-${var.api_name}-api-key"
  description = "Primary API key for ${var.api_name}"
  enabled     = true

  tags = var.tags
}

resource "aws_api_gateway_usage_plan_key" "this" {
  count = var.create_api_key ? 1 : 0

  key_id        = aws_api_gateway_api_key.this[0].id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.this.id
}

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
