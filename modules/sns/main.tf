resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts-topic"
}

# Configurar múltiplos endpoints
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "devops-team@example.com"
}

resource "aws_sns_topic_subscription" "slack" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "https"
  endpoint  = "https://hooks.slack.com/services/XXX/YYY/ZZZ"
}

resource "aws_sns_topic_subscription" "pagerduty" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "https"
  endpoint  = "https://events.pagerduty.com/XXX"
}

Mensagens de Exemplo para Alertas

[ALERTA] ${alarm_name}
Status: ${state_change_time}
Descrição: ${alarm_description}

Métrica: ${metric_name} = ${value} (Limite: ${threshold})
Recurso: ${resource_name}
Ação Recomendada: ${response_tag}

Detalhes: 
https://console.aws.amazon.com/cloudwatch/home?region=${region}#alarm:alarmFilter=ANY;name=${alarm_name}

EXEMPLO de Alerta
[ALERTA] flightradar-flights-throttling
Status: 2025-06-23T14:30:00Z
Descrição: ALTO VOLUME: Kinesis throttling detectado no stream de flights

Métrica: PutRecords.ThrottledRecords = 850 (Limite: 500)
Recurso: flightradar-flights-stream
Ação Recomendada: scale-up-shards

Detalhes: 
https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#alarm:alarmFilter=ANY;name=flightradar-flights-throttling