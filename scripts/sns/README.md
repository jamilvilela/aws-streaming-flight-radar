# SNS Module - Notifications for KDA Alerts

Módulo Terraform para provisionamento de um SNS Topic centralizado para notificações de alertas do KDA Flink.

## 📋 Overview

Este módulo cria:
- **SNS Topic** para receber alertas do KDA Flink
- **Email Subscriptions** (com confirmação manual)
- **Políticas de acesso** para CloudWatch e KDA service
- **SQS/Lambda Subscriptions** (opcional, para processamento customizado)
- **CloudWatch Alarm** para monitorar falhas de publicação SNS
- **Dead Letter Queue** para debugging

## 🏗️ Componentes

```
┌─────────────────────────────────────┐
│   CloudWatch Alarms (KDA)           │
│   • Failed checkpoints              │
│   • Job crashes                     │
│   • Data flow issues                │
└────────────┬────────────────────────┘
             │ (Publish message)
             ▼
┌─────────────────────────────────────┐
│   SNS Topic: kda-alerts             │ ◄─── This Module
│   ├─ Email subscriptions            │
│   ├─ SQS (optional)                 │
│   └─ Lambda (optional)              │
└────┬──────────────┬──────────────────┘
     │              │
     ▼              ▼
  Inbox         Custom Logic
  (Email)       (Processing)
```

## 🔧 Variáveis Requeridas

```hcl
sns = {
  project_name          = "flight-radar"
  environment           = "dev"
  alert_email_addresses = ["ops@company.com", "devops@company.com"]
}
```

## 🔑 Variáveis Opcionais

```hcl
sns = {
  project_name           = "flight-radar"
  environment            = "dev"
  alert_email_addresses  = ["ops@company.com"]
  
  # For async processing via SQS
  sqs_queue_arn          = "arn:aws:sqs:us-east-1:123456789:alert-queue"
  
  # For custom Lambda processing
  lambda_function_arn    = "arn:aws:lambda:us-east-1:123456789:function:process-alerts"
  
  # KMS encryption
  kms_key_id            = "arn:aws:kms:us-east-1:123456789:key/12345678"
  
  # Advanced
  allow_kda_publish     = true
  enable_delivery_status_logging = true
  create_publish_failure_alarm = true
  
  tags = var.tags
}
```

## 📤 Outputs

```hcl
sns_topic_arn          = "arn:aws:sns:us-east-1:123456789:flight-radar-kda-alerts"
sns_topic_name         = "flight-radar-kda-alerts"
email_subscription_arns = {
  "ops@company.com" = "arn:aws:sns:us-east-1:123456789:flight-radar-kda-alerts:12345678"
}
dlq_topic_arn          = "arn:aws:sns:us-east-1:123456789:flight-radar-kda-alerts-dlq"
sns_console_url        = "https://console.aws.amazon.com/sns/v3/home#/topic/..."
```

## 🚀 Como Usar

### 1. No `infra/main.tf`

```hcl
module "sns" {
  source = "./modules/sns"

  project_name          = var.project_name
  environment           = var.environment
  alert_email_addresses = ["ops@company.com"]
  
  allow_kda_publish     = true
  create_publish_failure_alarm = true
  
  tags = var.tags
}
```

### 2. Em `infra/variables.tf`

```hcl
variable "sns_config" {
  type = object({
    alert_email_addresses = list(string)
  })
  default = {
    alert_email_addresses = []
  }
}
```

### 3. Em `infra/tfvars/terraform.tfvars`

```hcl
sns_config = {
  alert_email_addresses = [
    "ops-team@company.com",
    "engineering@company.com"
  ]
}
```

### 4. Deploy

```bash
terraform plan
terraform apply

# Outputs
terraform output sns_topic_arn
terraform output email_subscription_arns
```

### 5. Confirmação de Subscriptions

1. Cada email receberá uma mensagem de confirmação do AWS SNS
2. Clique no link de confirmação
3. Subscription fica "Confirmed"
4. Alerta será entregue a partir de então

## 🔗 Integração com KDA

### Via módulo kda_flights

```hcl
module "kda_flights" {
  ...
  sns_topic_arn = module.sns.sns_topic_arn
}
```

### Via módulo redshift_serverless

```hcl
module "redshift_serverless" {
  ...
  sns_topic_arn = module.sns.sns_topic_arn
}
```

### Verificar subscriptions

```bash
aws sns list-subscriptions-by-topic \
  --topic-arn $(terraform output -raw sns_topic_arn)
```

## 📊 Tipos de Subscriptions Suportadas

| Tipo | Uso | Quando Usar |
|------|-----|-----------|
| **Email** | Notificações diretas na inbox | ✅ Padrão, sempre ativar |
| **SQS** | Fila para processamento async | Para alertas de alto volume |
| **Lambda** | Processamento customizado | Transformar/agregar/correlacionar alertas |
| **HTTP** | Webhooks customizados | Integrar com sistemas externos |
| **SMS** | Texto para celular | Alertas críticos (custo adicional) |

## 🔐 Segurança

### Permissões

```hcl
# Quem pode publicar no SNS topic:
1. CloudWatch (automatic)
2. KDA service (if allow_kda_publish=true)
3. Qualquer conta/user com permissão SNS:Publish
```

### Encryption

```hcl
# Optional: Criptografar mensagens com KMS
kms_key_id = "arn:aws:kms:us-east-1:123456789:key/12345678"
```

### Dead Letter Queue

```hcl
# SNS cria automaticamente um DLQ para:
# • Mensagens que falharam entrega
# • Debugging de falhas
output "dlq_topic_arn"
```

## 📈 Monitoramento

### CloudWatch Metrics (automático)

```bash
aws cloudwatch get-metric-statistics \
  --metric-name NumberOfMessagesPublished \
  --namespace AWS/SNS \
  --dimensions Name=TopicName,Value=flight-radar-kda-alerts \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

### Alarms criados por padrão

```hcl
# CloudWatch Alarm: SNS Publish Failures
# • Métrica: NumberOfNotificationsFailed
# • Threshold: > 0 por 5 minutos
# • Action: Notificar ops-team
```

## 🛠️ Troubleshooting

### Emails não chegando

```bash
# 1. Verificar subscription status
aws sns list-subscriptions-by-topic \
  --topic-arn arn:aws:sns:us-east-1:123456789:flight-radar-kda-alerts

# 2. Se PendingConfirmation, confirmar no email
# 3. Testar publicação manual
aws sns publish \
  --topic-arn arn:aws:sns:us-east-1:123456789:flight-radar-kda-alerts \
  --subject "Test Alert" \
  --message "This is a test notification"
```

### SNS Topic Policy erro

```bash
# Verificar policy
aws sns get-topic-attributes \
  --topic-arn arn:aws:sns:us-east-1:123456789:flight-radar-kda-alerts \
  --attribute-name Policy
```

## 📊 Custo Estimado

| Item | Custo Mensal |
|------|--------------|
| SNS Topic + Emails | ~$0 (free tier) |
| SQS delivery | ~$0 (5K messages/month) |
| Lambda invocations | Depende do volume |
| Total (low volume) | < $1/mês |

## 📚 Referências

- [AWS SNS Documentation](https://docs.aws.amazon.com/sns/latest/dg/)
- [SNS Subscriptions](https://docs.aws.amazon.com/sns/latest/dg/sns-create-subscribe-queue-to-topic.html)
- [SNS Delivery Status](https://docs.aws.amazon.com/sns/latest/dg/sns-topic-attributes.html)
- [Terraform aws_sns_topic](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic)

---

**Versão**: 1.0  
**Status**: ✅ Pronto para Produção  
**Última Atualização**: Abril 22, 2026
