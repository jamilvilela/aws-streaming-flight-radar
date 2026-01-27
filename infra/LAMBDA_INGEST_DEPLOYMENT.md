# Lambda Flight Ingest - Deployment Guide

## Overview

Este documento descreve o processo de deployment da função Lambda de ingestão de dados de voos da API OpenSky para o stream Kinesis.

## Arquitetura

```
OpenSky API
    ↓
Lambda Function (ingest-flights)
    ↓
Kinesis Data Stream (flight-radar-stream-flights)
    ↓
Downstream Processing (EventBridge triggered)
```

## Pré-requisitos

1. **Credenciais OpenSky API**
   - Usuário OpenSky ativo
   - Senha/API Key válida
   - Acesso à API OpenSky Network

2. **AWS Credentials**
   - AWS CLI configurado
   - Permissões IAM para criar Lambda, Kinesis, CloudWatch, IAM roles/policies

3. **Terraform**
   - Terraform >= 1.0
   - Backend S3 configurado (opcional)

## Configuração

### 1. Atualizar Credenciais OpenSky

Editar `infra/tfvars/terraform.tfvars`:

```terraform
opensky_credentials = {
  username = "seu_usuario_opensky"
  password = "sua_senha_opensky"
}
```

⚠️ **Segurança**: Para production, use Terraform Cloud, AWS Secrets Manager ou AWS SSM Parameter Store

### 2. Configurar Variáveis (Opcional)

```terraform
# Modificar timeout
lambda_ingest_timeout = 55  # segundos

# Habilitar VPC (se needed)
# No módulo lambda_ingest, definir enable_vpc = true
# Fornecer subnet_ids e security_group_ids

# Habilitar Lambda Insights
# No módulo lambda_ingest, definir enable_lambda_insights = true
```

## Deployment

### Via Deploy Script

```bash
cd infra
./deploy.sh
```

### Manual com Terraform

```bash
cd infra

# Inicializar Terraform
terraform init -var-file=tfvars/terraform.tfvars

# Validar configuração
terraform validate

# Visualizar plano
terraform plan -var-file=tfvars/terraform.tfvars

# Aplicar configurações
terraform apply -var-file=tfvars/terraform.tfvars
```

## Pós-Deployment

### 1. Verificar Criação de Recursos

```bash
# Verificar Lambda
aws lambda get-function \
  --function-name flight-radar-stream-ingest-flights \
  --region us-east-1

# Verificar Kinesis Stream
aws kinesis describe-stream \
  --stream-name flight-radar-stream-flights \
  --region us-east-1

# Verificar CloudWatch Logs
aws logs describe-log-groups \
  --log-group-name-prefix "/aws/lambda/flight-radar-stream-ingest-flights" \
  --region us-east-1
```

### 2. Testar Invocação Manual

```bash
# Criar arquivo de teste
cat > test_event.json << EOF
{
  "action": "get_states"
}
EOF

# Invocar Lambda
aws lambda invoke \
  --function-name flight-radar-stream-ingest-flights \
  --payload file://test_event.json \
  --region us-east-1 \
  response.json

# Verificar resposta
cat response.json
```

### 3. Monitorar CloudWatch Logs

```bash
# Visualizar logs em tempo real
aws logs tail \
  "/aws/lambda/flight-radar-stream-ingest-flights" \
  --region us-east-1 \
  --follow
```

## Environment Variables

A Lambda recebe as seguintes variáveis de ambiente:

| Variável | Descrição | Fonte |
|----------|-----------|-------|
| `KINESIS_STREAM` | Nome do stream Kinesis | Terraform |
| `OPENSKY_USER` | Usuário OpenSky API | Terraform |
| `OPENSKY_PASSWORD` | Senha OpenSky API | Terraform |
| `LOG_LEVEL` | Nível de log (INFO, DEBUG) | Terraform |

## IAM Permissions

A função Lambda possui as seguintes permissões:

- **Kinesis**: PutRecord, PutRecords, ListShards, ListStreams, DescribeStream
- **CloudWatch Logs**: CreateLogGroup, CreateLogStream, PutLogEvents
- **VPC** (se habilitado): ENI management

## Troubleshooting

### Erro: "Missing OPENSKY credentials"

**Causa**: Credenciais OpenSky não configuradas
**Solução**: Verificar `terraform.tfvars` e re-aplicar Terraform

```bash
terraform apply -var-file=tfvars/terraform.tfvars
```

### Erro: "Failed to send record to Kinesis"

**Causa**: Permissões IAM insuficientes ou stream não existe
**Solução**: 
1. Verificar se stream Kinesis foi criado
2. Verificar permissões IAM da Lambda

```bash
aws kinesis list-streams --region us-east-1
```

### Lambda Timeout

**Causa**: Tempo de execução excedeu o limite
**Solução**: Aumentar timeout em `variables.tf`:

```terraform
variable "timeout" {
  default = 120  # aumentar para 120 segundos
}
```

### Credenciais OpenSky expiradas

**Causa**: Senha/token OpenSky invalida
**Solução**: Atualizar credenciais em `terraform.tfvars` e fazer deploy novamente

## Custos Estimados

- **Lambda**: ~$0.20/milhão de invocações
- **Kinesis**: ~$0.40/hora por shard
- **CloudWatch Logs**: ~$0.50/GB ingerido

**Exemplo**: 60 invocações/hora × 24h = 1.440 invocações/dia
- Custo Lambda: ~$0.002/dia
- Custo Kinesis: ~$9.60/dia (1 shard)

## Próximas Etapas

1. Configurar EventBridge para disparar Lambda periodicamente
2. Implementar Lambda de processamento (stream consumer)
3. Adicionar DynamoDB para cache de metadados
4. Configurar alertas CloudWatch

## Suporte

Para mais informações, consulte:
- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [Amazon Kinesis Documentation](https://docs.aws.amazon.com/kinesis/)
- [OpenSky Network API](https://opensky-network.org/apidoc/)
