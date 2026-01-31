data "archive_file" "lambda_processor" {
  for_each    = toset(keys(var.kinesis_arns))
  type        = "zip"
  source_dir  = "lambda_src/process_${each.key}"
  output_path = "lambda_process_${each.key}.zip"
}

resource "aws_lambda_function" "processor" {
  for_each      = data.archive_file.lambda_processor
  function_name = "${var.project_name}-process-${each.key}"
  role          = aws_iam_role.processor_role[each.key].arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  timeout       = var.timeout
  filename      = each.value.output_path
  source_code_hash = each.value.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE = each.key
    }
  }
}

resource "aws_lambda_event_source_mapping" "kinesis_trigger" {
  for_each = var.kinesis_arns
  
  event_source_arn  = each.value
  function_name     = aws_lambda_function.processor[each.key].arn
  starting_position = "LATEST"

  # Configurações anti-backpressure
  batch_size = each.key == "flights" ? 1000 : 100
  maximum_batching_window_in_seconds = 5
  parallelization_factor = each.key == "flights" ? 10 : 2
  maximum_retry_attempts = 3

  scaling_config {
    maximum_concurrency = each.key == "flights" ? 1000 : 100
  }
}

resource "aws_iam_role" "processor_role" {
  for_each = toset(keys(var.kinesis_arns))
  name = "${var.project_name}-process-${each.key}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "dynamodb_write" {
  for_each   = toset(keys(var.kinesis_arns))
  role       = aws_iam_role.processor_role[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_role_policy_attachment" "kinesis_read" {
  for_each   = toset(keys(var.kinesis_arns))
  role       = aws_iam_role.processor_role[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonKinesisReadOnlyAccess"
}

resource "aws_lambda_event_source_mapping" "kinesis_trigger" {
  for_each         = toset(keys(var.kinesis_arns))
  event_source_arn = var.kinesis_arns[each.key]
  function_name    = aws_lambda_function.processor[each.key].arn
  starting_position = "LATEST"
  batch_size       = 100
}