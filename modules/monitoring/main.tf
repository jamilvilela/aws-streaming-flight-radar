resource "aws_cloudwatch_dashboard" "data_pipeline" {
  dashboard_name = "${var.project_name}-high-volume"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 24
        height = 6
        properties = {
          metrics = [
            ["AWS/Kinesis", "PutRecords.Success", "StreamName", "flights-stream"],
            [".", "PutRecords.Throttled", ".", "."],
            [".", "GetRecords.Success", ".", "."],
            ["AWS/Lambda", "Throttles", "FunctionName", "${var.project_name}-ingest-flights"]
          ],
          period = 10,
          stat   = "Sum"
        }
      }
    ]
  })
}

# alertas automáticos
resource "aws_cloudwatch_metric_alarm" "kinesis_throttling" {
  alarm_name          = "${var.project_name}-flights-throttling"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5  # Amostras consecutivas
  datapoints_to_alarm = 3  # 3/5 amostras acima do limite
  metric_name         = "PutRecords.ThrottledRecords"
  namespace           = "AWS/Kinesis"
  period              = 60  # Segundos
  statistic           = "Sum"
  threshold           = 500  # Registros throttled por minuto
  alarm_description   = "ALTO VOLUME: Kinesis throttling detectado no stream de flights"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    StreamName = aws_kinesis_stream.flights_stream.name
  }

  tags = {
    Severity    = "critical"
    Component   = "kinesis"
    Response    = "scale-up-shards"
  }
}

resource "aws_cloudwatch_metric_alarm" "kinesis_lag" {
  alarm_name          = "${var.project_name}-flights-lag"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "GetRecords.IteratorAgeMilliseconds"
  namespace           = "AWS/Kinesis"
  period              = 60
  statistic           = "Maximum"
  threshold           = 300000  # 5 minutos em ms
  alarm_description   = "ATRASO CRÍTICO: Processamento de flights está atrasado"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    StreamName = aws_kinesis_stream.flights_stream.name
  }

  tags = {
    Severity    = "high"
    Component   = "lambda-processor"
    Response    = "check-lambda-scaling"
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project_name}-flights-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 10  # 10 erros/minuto
  alarm_description   = "FALHA: Erros na função de processamento de flights"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    FunctionName = aws_lambda_function.flights_processor.function_name
  }

  tags = {
    Severity    = "critical"
    Component   = "lambda"
    Response    = "check-logs"
  }
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_throttling" {
  alarm_name          = "${var.project_name}-flights-ddb-throttling"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  metric_name         = "ThrottledRequests"
  namespace           = "AWS/DynamoDB"
  period              = 60
  statistic           = "Sum"
  threshold           = 100  # Requisições throttled
  alarm_description   = "CAPACIDADE: DynamoDB throttling em flights table"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    TableName = aws_dynamodb_table.flights_table.name
  }

  tags = {
    Severity    = "medium"
    Component   = "dynamodb"
    Response    = "enable-auto-scaling"
  }
}