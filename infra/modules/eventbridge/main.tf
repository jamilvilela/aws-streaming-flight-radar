resource "aws_cloudwatch_event_rule" "ingestion_schedule" {
  for_each            = var.lambda_arns
  name                = "${split("-", each.key)[2]}-schedule"
  schedule_expression = var.schedule
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  for_each = var.lambda_arns
  rule     = aws_cloudwatch_event_rule.ingestion_schedule[each.key].name
  arn      = each.value
}

resource "aws_lambda_permission" "allow_eventbridge" {
  for_each      = var.lambda_arns
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = split(":", each.value)[6]
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ingestion_schedule[each.key].arn
}