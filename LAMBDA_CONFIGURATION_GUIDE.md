# Lambda Functions Configuration Guide

## Overview

A estrutura de configuração suporta **múltiplas funções Lambda** com suas configurações individuais em um único mapa/dicionário.

## Estrutura de Dados


```terraform
lambda_functions = {
  flights = {
    name              = "ingest-flights"
    handler           = "lambda_function.lambda_handler"
    runtime           = "python3.12"
    timeout           = 55
    memory_size       = 2048
    ephemeral_storage = 10240
    schedule          = "rate(60 seconds)"
    enabled           = true
    kinesis_stream    = "flight-radar-stream-flights"
    requires_opensky_credentials = true
    reserved_concurrent_executions = 100
    tags = {
      Type   = "ingest"
      Source = "opensky-api"
    }
  }
}
```

## Campos de Configuração

| Campo | Tipo | Descrição | Exemplo |
|-------|------|-----------|---------|
| `name` | string | Nome descritivo da função | `"ingest-flights"` |
| `handler` | string | Handler da Lambda | `"lambda_function.lambda_handler"` |
| `runtime` | string | Runtime Python | `"python3.12"` |
| `timeout` | number | Timeout em segundos (1-900) | `55` |
| `memory_size` | number | Memória em MB (128-10240) | `2048` |
| `ephemeral_storage` | number | Storage efêmero em MB (512-10240) | `10240` |
| `schedule` | string | Expressão de agendamento EventBridge | `"rate(60 seconds)"` |
| `enabled` | bool | Se a Lambda está habilitada | `true` |
| `kinesis_stream` | string | Nome do stream Kinesis de destino | `"flight-radar-stream-flights"` |
| `requires_opensky_credentials` | bool | Se precisa de credenciais OpenSky | `true` |
| `reserved_concurrent_executions` | number | Concorrência reservada | `100` |
| `tags` | map(string) | Tags específicas da função | `{ Type = "ingest" }` |

## Exemplos de Configuração

### 1. Função de Ingestão de Voos (Atual)

```terraform
lambda_functions = {
  flights = {
    name              = "ingest-flights"
    handler           = "lambda_function.lambda_handler"
    runtime           = "python3.12"
    timeout           = 55
    memory_size       = 2048
    ephemeral_storage = 10240
    schedule          = "rate(60 seconds)"
    enabled           = true
    kinesis_stream    = "flight-radar-stream-flights"
    requires_opensky_credentials = true
    reserved_concurrent_executions = 100
    tags = {
      Type   = "ingest"
      Source = "opensky-api"
    }
  }
}
```

### 2. Adicionando Função de Aeroportos

```terraform
lambda_functions = {
  flights = {
    # ... configuração flights acima ...
  }
  
  airports = {
    name              = "ingest-airports"
    handler           = "lambda_function.lambda_handler"
    runtime           = "python3.12"
    timeout           = 60
    memory_size       = 1024
    ephemeral_storage = 5120
    schedule          = "rate(1 hour)"
    enabled           = true
    kinesis_stream    = "flight-radar-stream-airports"
    requires_opensky_credentials = false
    reserved_concurrent_executions = 10
    tags = {
      Type   = "ingest"
      Source = "external-api"
    }
  }
}
```

### 3. Desabilitar uma Função

Para desabilitar temporariamente uma função sem removê-la:

```terraform
lambda_functions = {
  flights = {
    # ... todas as configurações ...
    enabled = false  # ← Desabilita
  }
}
```

## Expressões de Agendamento (Schedule)

### Formato: `rate(value unit)`

```terraform
# A cada N unidades
"rate(60 seconds)"      # cada 60 segundos
"rate(5 minutes)"       # a cada 5 minutos
"rate(1 hour)"          # a cada 1 hora
"rate(1 day)"           # uma vez por dia
```

### Formato: `cron(minute hour day month ? year)`

```terraform
# Hora específica
"cron(0 12 * * ? *)"    # 12:00 UTC todos os dias
"cron(0 * * * ? *)"     # cada hora
"cron(0 */6 * * ? *)"   # a cada 6 horas
"cron(0 0 1 * ? *)"     # 1º dia do mês
```

## Arquitetura Dinâmica

### Fluxo com Múltiplas Lambdas

```
terraform.tfvars (lambda_functions)
           ↓
variables.tf (map com validações)
           ↓
main.tf (loop: for_each)
        ├─ module.lambda_ingest[flights]
        ├─ module.lambda_ingest[airports]
        └─ module.lambda_ingest[...]
        ├─ module.eventbridge[flights]
        ├─ module.eventbridge[airports]
        └─ module.eventbridge[...]
```

### Modularização

Cada Lambda recebe:

1. **lambda_key**: Identificador único (`flights`, `airports`, etc.)
2. **lambda_config**: Objeto com todas as configurações
3. **kinesis_streams**: Mapa de streams disponíveis

Isso permite que cada módulo seja:
- ✅ Independente
- ✅ Reutilizável
- ✅ Configurável

## Validações

O Terraform aplica automaticamente validações:

```terraform
validation {
  condition = alltrue([
    for func in var.lambda_functions :
    func.timeout > 0 && func.timeout <= 900
  ])
  error_message = "Lambda timeout deve ser entre 1 e 900 segundos."
}
```

## Deploy

### Visualizar Plano

```bash
terraform plan -var-file=tfvars/terraform.tfvars
```

Exemplo de saída:

```
+ module.lambda_ingest["flights"].aws_lambda_function.lambda_function
+ module.lambda_ingest["flights"].aws_cloudwatch_event_rule.lambda_schedule
+ module.lambda_ingest["airports"].aws_lambda_function.lambda_function
  [...]
```

### Aplicar Configurações

```bash
terraform apply -var-file=tfvars/terraform.tfvars
```

### Alterar Uma Única Função

Para alterar apenas a função `flights`:

```bash
terraform apply \
  -var-file=tfvars/terraform.tfvars \
  -target='module.lambda_ingest["flights"]'
```

## Outputs

Após o deploy, os outputs incluem todas as funções:

```terraform
lambda_functions = {
  flights = {
    arn  = "arn:aws:lambda:us-east-1:123:function:flight-radar-stream-ingest-flights"
    name = "flight-radar-stream-ingest-flights"
  }
  airports = {
    arn  = "arn:aws:lambda:us-east-1:123:function:flight-radar-stream-ingest-airports"
    name = "flight-radar-stream-ingest-airports"
  }
}
```

## Best Practices

### 1. Naming Convention

Mantenha um padrão nos nomes:

```terraform
lambda_functions = {
  flights = {
    name = "ingest-flights"        # ✅ Bom
    # name = "FlightsIngest"       # ❌ Inconsistente
  }
  
  airports = {
    name = "ingest-airports"       # ✅ Bom
  }
}
```

### 2. Credenciais

Sensíveis devem estar em `terraform.tfvars` e **não no controle de versão**:

```bash
# .gitignore
**/terraform.tfvars
**/*.tfvars
```

### 3. Tags Padrão

Combine tags globais com específicas:

```terraform
# Em terraform.tfvars
tags = {
  Environment = "production"
  Project     = "flight-radar-stream"
  ManagedBy   = "terraform"
}

lambda_functions = {
  flights = {
    # ...
    tags = {
      Type   = "ingest"           # ← Específica
      Source = "opensky-api"      # ← Específica
    }
    # Terraform faz merge com tags globais
  }
}
```

### 4. Escalabilidade

Ao adicionar nova Lambda:

1. Copie um bloco existente no `lambda_functions`
2. Altere a chave (ex: `flights` → `airports`)
3. Atualize os campos necessários
4. Crie o diretório `app/src/ingest_airports/`
5. Faça `terraform apply`

## Troubleshooting

### Erro: "Stream não existe"

```
Error: Error creating Lambda function: ValidationException: The role arn:aws:iam::123:role/... assumed the role, but it does not have permission...
```

**Solução**: Verifique se `kinesis_stream` corresponde a uma chave em `kinesis_streams`.

### Erro: "Timeout deve estar entre 1 e 900"

Se você definir `timeout = 1000`:

```
Error: Invalid value for lambda_functions: Lambda timeout deve ser entre 1 e 900 segundos.
```

**Solução**: Reduza para 900 ou aumente o tipo de computação.

### Lambda não sendo disparada

**Causa**: `enabled = false`

**Solução**:

```terraform
lambda_functions = {
  flights = {
    # ...
    enabled = true  # ← Mude para true
  }
}
```

## Próximas Etapas

1. ✅ Refatoração com múltiplas Lambdas concluída
2. 🔄 Adicionar novas funções conforme necessário
3. 📊 Implementar monitoramento centralizado
4. 🔐 Usar AWS Secrets Manager para credenciais

## Referências

- [Terraform for_each Loops](https://www.terraform.io/language/meta-arguments/for_each)
- [AWS Lambda Configuration](https://docs.aws.amazon.com/lambda/latest/dg/lambda-functions.html)
- [EventBridge Schedules](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-create-rule.html)
