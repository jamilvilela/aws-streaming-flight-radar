# Kinesis Data Stream - Lambda Ingest Integration

## Overview

O módulo Kinesis Data Stream foi otimizado para receber dados da Lambda `ingest-flights` de forma eficiente e econômica.

## Arquitetura de Integração

```
Lambda ingest-flights                Kinesis Data Stream
    ↓                                      ↓
1. Fetch OpenSky API            1. ON-DEMAND mode
2. Parse JSON (7.5 MB)          2. Auto-scaling
3. PutRecord × N                3. 24h retention
    ↓                                      ↓
    Partition Key: icao24       → Shard assignment
                                         ↓
                                Downstream consumer
                                (processor Lambda)
```

## Alterações Realizadas

### 1. **Modo de Stream: PROVISIONED → ON-DEMAND**

**Antes**:
```terraform
stream_mode_details {
  stream_mode = "PROVISIONED"  # Shards fixos, custo constante
}
```

**Depois**:
```terraform
stream_mode_details {
  stream_mode = "ON_DEMAND"    # Auto-scaling, pay-per-use
}
```

**Benefício**: 
- ✅ Sem gerenciamento manual de shards
- ✅ Escalação automática
- ✅ Pagamento por demanda real
- ✅ Perfeito para volume baixo (1.440 invocações/dia)

### 2. **Nomes de Stream Dinâmicos**

**Antes**:
```terraform
name = "kinesis-data-stream-${each.key}"
```

**Depois**:
```terraform
name = each.value.stream_name  # Do tfvars: "flight-radar-stream-flights"
```

**Benefício**: 
- ✅ Nomes customizáveis
- ✅ Consistência com Lambda

### 3. **Monitoramento Automático**

Adicionados alarmes CloudWatch:

```terraform
# Alerta quando iterador envelhece (>60s)
aws_cloudwatch_metric_alarm "kinesis_iterator_age"

# Alerta quando nenhum registro entra por 5+ minutos
aws_cloudwatch_metric_alarm "kinesis_incoming_records"
```

### 4. **Outputs Expandidos**

```terraform
kinesis_streams_info = {
  flights = {
    name              = "flight-radar-stream-flights"
    arn               = "arn:aws:kinesis:us-east-1:...:stream/..."
    status            = "ACTIVE"
    retention_hours   = 24
    mode              = "ON_DEMAND"
  }
}
```

## Fluxo de Dados: Lambda → Kinesis

### 1. Lambda Busca Dados
```python
states = await api.get_states()  # ~7.5 MB JSON com 7500 itens
json_resultado = convert_states_response_to_json(states)
```

### 2. Lambda Envia para Kinesis
```python
kinesis_client.put_record(
    StreamName="flight-radar-stream-flights",  # Nome do stream
    Data=json.dumps(state_dict),               # ~1 KB por registro
    PartitionKey=state_dict['icao24']          # Distribuição por aeronave
)
```

### 3. Kinesis Armazena e Escalona
- **Modo**: ON-DEMAND (escalação automática)
- **Retenção**: 24 horas
- **Particionamento**: Por `icao24` (cada aeronave → mesmo shard)

### 4. Consumer Lê do Stream
```python
# Processor Lambda (futura implementação)
# Lê batches de registros
for record in shard_iterator:
    flight_data = json.loads(record['Data'])
    # Processar, enriquecer, armazenar em DynamoDB
```

## Configuração em terraform.tfvars

```terraform
kinesis_streams = {
  flights = { 
    stream_name = "flight-radar-stream-flights"
    shard_count = 1  # Ignorado em ON_DEMAND (manter para compatibilidade)
  }  
}
```

## Custos Estimados

### Cálculo para 1.440 invocações/dia

**Ingestão (Lambda → Kinesis)**:
- 1.440 registros/dia
- ~1 KB por registro
- ~1.44 MB/dia = 43.2 MB/mês
- Cost: ~$0.02/mês (ingestão)

**Armazenamento**:
- 43.2 MB retidos por 24h
- Cost: ~$0.001/mês

**Leitura (by consumer)**:
- Depends on consumer Lambda (future)
- Estimated: ~$0.01/mês

**Total**: ~$0.03/mês para Kinesis (muito barato!)

## Escalabilidade

### Se Volume Aumentar (ex: 10x mais dados)

Com ON-DEMAND mode, Kinesis **automaticamente**:
1. ✅ Aumenta throughput
2. ✅ Gerencia shards internamente
3. ✅ Não requer mudança de código/config
4. ✅ Custo escala com uso real

### Se Mudar para Modo PROVISIONED

Se precisar de SLA muito rígido no futuro:

```terraform
stream_mode_details {
  stream_mode = "PROVISIONED"
}
shard_count = 2  # Número de shards
```

Estimativa: 1 shard = ~$0.20/hora = ~$150/mês

## Monitoramento

### CloudWatch Dashboards (Recomendado)

```bash
# Ver métricas do stream
aws cloudwatch get-metric-statistics \
  --namespace AWS/Kinesis \
  --metric-name IncomingRecords \
  --dimensions Name=StreamName,Value=flight-radar-stream-flights \
  --start-time 2026-01-20T00:00:00Z \
  --end-time 2026-01-20T23:59:59Z \
  --period 3600 \
  --statistics Sum
```

### Alarmes Configurados

1. **Iterator Age**: Alerta se registros não são lidos por >60 segundos
2. **Incoming Records**: Alerta se nenhum registro entra por 5+ minutos

## Segurança

### IAM Permissions (Já Configurado)

Lambda tem permissões para:
- ✅ `kinesis:PutRecord` - Enviar registros
- ✅ `kinesis:PutRecords` - Enviar batch
- ✅ `kinesis:DescribeStream` - Verificar status

## Troubleshooting

### "AccessDenied" ao enviar para Kinesis

**Causa**: IAM role da Lambda não tem permissão

**Solução**: Verificar que Lambda role tem política Kinesis

```bash
aws iam list-role-policies --role-name flight-radar-stream-lambda-flights-role
```

### Stream em estado "CREATING"

**Esperado**: Leva 5-15 minutos após `terraform apply`

**Solução**: Aguarde antes de invocar Lambda

```bash
aws kinesis describe-stream \
  --stream-name flight-radar-stream-flights
```

### Nenhum dado chegando ao stream

**Checklist**:
1. ✅ Lambda está sendo disparada? (CloudWatch Logs)
2. ✅ Lambda tem erro? (Check logs)
3. ✅ Stream está ACTIVE? (describe-stream)
4. ✅ IAM permissions OK? (list-role-policies)

## Próximas Etapas

1. ✅ Kinesis stream criado (ON-DEMAND)
2. ✅ Lambda enviando dados (PutRecord)
3. ⏳ Implementar Consumer (Processor Lambda)
4. ⏳ Armazenar em DynamoDB
5. ⏳ Analytics/Dashboards

## Referências

- [AWS Kinesis Pricing](https://aws.amazon.com/kinesis/data-streams/pricing/)
- [ON-DEMAND vs PROVISIONED](https://docs.aws.amazon.com/kinesis/latest/dev/kinesis-using-sdks.html)
- [Partition Keys](https://docs.aws.amazon.com/kinesis/latest/dev/service-supported-sample-records.html)
