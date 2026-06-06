resource "aws_api_gateway_rest_api" "this" {
  count       = var.create_api_gateway ? 1 : 0
  name        = "${var.project_name}-${var.api_name}"
  description = var.api_description

  endpoint_configuration {
    types = [var.endpoint_type]
  }

  tags = var.tags
}

resource "aws_api_gateway_resource" "flights" {
  count       = var.create_api_gateway ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.this[0].id
  parent_id   = aws_api_gateway_rest_api.this[0].root_resource_id
  path_part   = "flights"
}

resource "aws_api_gateway_resource" "flights_batch" {
  count       = var.create_api_gateway ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.this[0].id
  parent_id   = aws_api_gateway_resource.flights[0].id
  path_part   = "batch"
}

# ---------------- /flights (single record POST) ----------------
resource "aws_api_gateway_method" "post_flights" {
  count            = var.create_api_gateway ? 1 : 0
  rest_api_id      = aws_api_gateway_rest_api.this[0].id
  resource_id      = aws_api_gateway_resource.flights[0].id
  http_method      = "POST"
  authorization    = "CUSTOM"
  authorizer_id    = aws_api_gateway_authorizer.this[0].id
  api_key_required = true
}

resource "aws_api_gateway_integration" "post_flights_lambda" {
  count                   = var.create_api_gateway ? 1 : 0
  rest_api_id             = aws_api_gateway_rest_api.this[0].id
  resource_id             = aws_api_gateway_resource.flights[0].id
  http_method             = aws_api_gateway_method.post_flights[0].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arn
}

# ---------------- /flights/batch (multi record POST) ----------------
resource "aws_api_gateway_method" "post_flights_batch" {
  count            = var.create_api_gateway ? 1 : 0
  rest_api_id      = aws_api_gateway_rest_api.this[0].id
  resource_id      = aws_api_gateway_resource.flights_batch[0].id
  http_method      = "POST"
  authorization    = "CUSTOM"
  authorizer_id    = aws_api_gateway_authorizer.this[0].id
  api_key_required = true
}

resource "aws_api_gateway_integration" "post_flights_batch_lambda" {
  count                   = var.create_api_gateway ? 1 : 0
  rest_api_id             = aws_api_gateway_rest_api.this[0].id
  resource_id             = aws_api_gateway_resource.flights_batch[0].id
  http_method             = aws_api_gateway_method.post_flights_batch[0].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arn
}

# ---------------- /flights (GET - healthcheck shape) ----------------
resource "aws_api_gateway_method" "get_flights" {
  count            = var.create_api_gateway ? 1 : 0
  rest_api_id      = aws_api_gateway_rest_api.this[0].id
  resource_id      = aws_api_gateway_resource.flights[0].id
  http_method      = "GET"
  authorization    = "CUSTOM"
  authorizer_id    = aws_api_gateway_authorizer.this[0].id
  api_key_required = true
}

resource "aws_api_gateway_integration" "get_flights_lambda" {
  count                   = var.create_api_gateway ? 1 : 0
  rest_api_id             = aws_api_gateway_rest_api.this[0].id
  resource_id             = aws_api_gateway_resource.flights[0].id
  http_method             = aws_api_gateway_method.get_flights[0].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arn
}

# ---------------- Authorizer ----------------
resource "aws_api_gateway_authorizer" "this" {
  count                            = var.create_api_gateway ? 1 : 0
  name                             = "${var.project_name}-${var.api_name}-authorizer"
  rest_api_id                      = aws_api_gateway_rest_api.this[0].id
  authorizer_uri                   = var.authorizer_invoke_arn
  authorizer_credentials           = aws_iam_role.apigateway_authorizer[0].arn
  type                             = "TOKEN"
  identity_source                  = "method.request.header.X-Api-Key"
  authorizer_result_ttl_in_seconds = 300
}

# ---------------- Deployment ----------------
resource "aws_api_gateway_deployment" "this" {
  count       = var.create_api_gateway ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.this[0].id

  triggers = {
    redeploy = sha1(jsonencode([
      aws_api_gateway_resource.flights[0].id,
      aws_api_gateway_resource.flights_batch[0].id,
      aws_api_gateway_method.post_flights[0].id,
      aws_api_gateway_method.post_flights_batch[0].id,
      aws_api_gateway_method.get_flights[0].id,
      aws_api_gateway_integration.post_flights_lambda[0].id,
      aws_api_gateway_integration.post_flights_batch_lambda[0].id,
      aws_api_gateway_integration.get_flights_lambda[0].id,
      aws_api_gateway_authorizer.this[0].id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "this" {
  count         = var.create_api_gateway ? 1 : 0
  rest_api_id   = aws_api_gateway_rest_api.this[0].id
  deployment_id = aws_api_gateway_deployment.this[0].id
  stage_name    = var.stage_name

  dynamic "access_log_settings" {
    for_each = var.enable_access_logs ? [1] : []
    content {
      destination_arn = aws_cloudwatch_log_group.apigw_access[0].arn
      format          = local.access_log_format
    }
  }

  tags = var.tags

  depends_on = [
    aws_api_gateway_account.this,
  ]
}

# ---------------- Usage Plan + API Key ----------------
resource "aws_api_gateway_usage_plan" "this" {
  count       = var.create_api_gateway ? 1 : 0
  name        = "${var.project_name}-${var.api_name}-usage-plan"
  description = "Throttling and quota for the ${var.api_name} API"

  api_stages {
    api_id = aws_api_gateway_rest_api.this[0].id
    stage  = aws_api_gateway_stage.this[0].stage_name
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
  count = var.create_api_gateway && var.create_api_key ? 1 : 0

  name        = "${var.project_name}-${var.api_name}-api-key"
  description = "Primary API key for ${var.api_name}"
  enabled     = true

  tags = var.tags
}

resource "aws_api_gateway_usage_plan_key" "this" {
  count = var.create_api_gateway && var.create_api_key ? 1 : 0

  key_id        = aws_api_gateway_api_key.this[0].id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.this[0].id
}
