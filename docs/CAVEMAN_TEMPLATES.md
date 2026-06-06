# Caveman Response Templates — Quick Patterns

Use esses templates para respostas rápidas, diretas, efetivas.

---

## Template 1: Error → Fix

```
✗ PROBLEMA: [descrever erro]
  Locação: [arquivo:linha]
  Impacto: [bloqueador/crítico/cosmético]

✓ FIX: [solução concisa]
  Antes:  [código ruim]
  Depois: [código bom]

Why: [1 linha explicação técnica]
```

**Exemplo**:
```
✗ PROBLEMA: Lambda não consegue ler Secrets Manager
  Locação: iam.tf (lambda_kinesis policy)
  Impacto: bloqueador (pipeline falha no start)

✓ FIX: Adicionar policy secretsmanager:GetSecretValue
  Antes:  data "aws_iam_policy_document" "lambda_kinesis" { ... }
  Depois: + data "aws_iam_policy_document" "lambda_secrets_manager" { ... }

Why: IAM deny-by-default; precisa permissão explícita
```

---

## Template 2: Architecture Decision

```
arq: [situação]
  @[contexto/ambiente]
  
stack: [componentes] 
  → [fluxo/pipeline]
  → [output]

trade-offs:
  [option A]: ✓ [benefit] | ✗ [cost]
  [option B]: ✓ [benefit] | ✗ [cost]

✓ recomendação: [opção] porque [motivo]

latência: [tempo esperado]
custo: [estimativa]
```

**Exemplo**:
```
arq: event-driven streaming ingestão voos
  @AWS (Kinesis + Flink + S3)
  
stack: Lambda→Kinesis→KDA→Parquet
  → JSON batch (OpenSky API)
  → Flink SQL enriquecimento
  → S3 particionado por hora

trade-offs:
  Lambda+Kinesis: ✓ managed serverless | ✗ costs >$500/mo
  Airflow+Spark:  ✓ fine-grained control | ✗ operational burden
  EventBridge:    ✓ native scheduling | ✗ cold start latency

✓ recomendação: Lambda+Kinesis porque alinha com cost/complexity tradeoff

latência: < 5 min e2e (aceitável para reporting)
custo: $50/mo dev, $500+/mo prod
```

---

## Template 3: Code Review Comment

```
[LINHA NN]: [símbolo] [problema]
  ✗ atual: [snippet]
  ✓ sugestão: [snippet]
  ? por quê: [explicação breve]
```

**Exemplo**:
```
[line 45]: ✗ hardcoded ARN não portável entre contas
  ✗ atual: 'stream.arn' = 'arn:aws:kinesis:us-east-1:331504768406:...'
  ✓ sugestão: 'stream.arn' = '${KINESIS_STREAM_ARN}'
  ? por quê: variáveis via environment properties em runtime

[line 37]: ✗ PROCTIME errado para janelas time-based
  ✗ atual: event_time AS PROCTIME()
  ✓ sugestão: CURRENT_TIMESTAMP AS event_time ROWTIME
  ? por quê: PROCTIME = hora processamento (errado); ROWTIME = hora evento (correto)

[line 114]: ✗ sem retry logic em falhas transientes
  ✗ atual: response = kinesis_client.put_records(...)
  ✓ sugestão: com try/except + exponential backoff
  ? por quê: throttling/transient errors precisam retry; código atual perde dados
```

---

## Template 4: Comparison Table

```
| aspecto | [OPTION A] | [OPTION B] | why? |
|---------|-----------|-----------|------|
| performance | [X ms] | [Y ms] | A > B porque [reason] |
| cost | [$X/mo] | [$Y/mo] | B > A porque [reason] |
| maintenance | [high/med/low] | [high/med/low] | trade-off: [explica] |
| scalability | [limite] | [limite] | [recomendação] |
```

**Exemplo**:
```
| aspecto | Kinesis ON_DEMAND | Kinesis PROVISIONED | why? |
|---------|------------------|-------------------|------|
| latency | ~100ms p99 | ~50ms p99 | ON_DEMAND + slight overhead |
| cost | $0.36/hour | $0.34/shard·hour | ON_DEMAND melhor <5 shards |
| scaling | instant (pay-per) | manual + auto-scaling | ON_DEMAND better dev |
| setup | zero config | shards + targets | ON_DEMAND simpler |

✓ recomendação: ON_DEMAND p/ dev (<$10/mo); PROVISIONED p/ prod (cost optimization)
```

---

## Template 5: Incident Report

```
! INCIDENT: [título]
  Hora: [timestamp]
  Duração: [min]
  Impacto: [quantitativo]

Timeline:
  T+0min: [que aconteceu]
  T+X min: [ação tomada]
  T+Y min: [root cause identificado]
  T+Z min: [fix deployado]

Root Cause: [explicação técnica]

Fix: [o que fez]

Prevention: [o que evita acontecer novamente]
```

**Exemplo**:
```
! INCIDENT: Lambda falhou 500x em 1h (credentials)
  Hora: Jun 5, 13:42 UTC
  Duração: 58 min
  Impacto: 0 eventos processados; dados perdidos

Timeline:
  T+0min: Lambda começou, AccessDenied on Secrets Manager
  T+15min: On-call alertado via Slack
  T+25min: Identificado: IAM policy faltando
  T+58min: Fix deployado (terraform apply)

Root Cause: Secrets Manager policy não existia no iam.tf
            Faltava: Action = ["secretsmanager:GetSecretValue"]

Fix: Adicionada policy + terraform apply

Prevention:
  ✓ Adicionar checklist: "Validate IAM policies before deploy"
  ✓ Adicionar test: synthetic Lambda invoke (pré-deploy)
  ✓ Aumentar alarm sensitivity: alert at first error
```

---

## Template 6: Documentation Entry

```
# [TITULO]

! contexto: [situação] @[ambiente]

código:
\`\`\`[language]
[snippet]
\`\`\`

notas:
  + [detalhe importante]
  ! [atenção especial]
  ? [dúvida comum]
  ✓ [best practice]
  ✗ [anti-pattern]

referencias:
  [link1 - descrição]
  [link2 - descrição]
```

**Exemplo**:
```
# Flink SQL: Event Time vs Processing Time

! contexto: time-based aggregations em streaming @Flink

código:
\`\`\`sql
-- ✗ errado (usa tempo processamento)
event_time AS PROCTIME()

-- ✓ correto (usa tempo evento)
CURRENT_TIMESTAMP AS event_time ROWTIME
\`\`\`

notas:
  + PROCTIME = momento que Flink processa o dado (variável!)
  + ROWTIME = timestamp do evento (imutável, correto)
  ! Janelas TUMBLE/HOP EXIGEM ROWTIME
  ? se event late > watermark? → descartado (acceptable)
  ✓ always use ROWTIME for time-driven aggregations
  ✗ never PROCTIME em TUMBLE/HOP (não funciona!)

referencias:
  https://nightlies.apache.org/flink/flink-docs-master/docs/dev/table/sql/overview/
  app/flink-sql-application/02_enriched_view.sql
```

---

## Template 7: Quick Status Update

```
status: [🟢 ON_TRACK | 🟡 AT_RISK | 🔴 BLOCKED]

done ✓:
  + [item 1]
  + [item 2]

in_progress 🔄:
  + [item A] (ETA: day)
  + [item B] (ETA: day)

blocked 🔴:
  + [issue X] (waiting: resource)
  + [issue Y] (reason: blocker Z)

next 👉:
  → [ação prioritária]
  → [ação secundária]
```

**Exemplo**:
```
status: 🟢 ON_TRACK

done ✓:
  + 4 erros críticos resolvidos (100%)
  + 7 melhorias implementadas
  + 11 arquivos corrigidos
  + Terraform validado

in_progress 🔄:
  + Documentation (ETA: today 17:00)
  + Deploy manual testing (ETA: tomorrow 09:00)

blocked 🔴:
  + Production deploy (waiting: security approval)

next 👉:
  → Prepare terraform.tfvars w/ real values
  → Run terraform apply in dev account
  → Monitor logs + metrics (first 24h)
```

---

## Template 8: Technical Decision Record (ADR)

```
# ADR-NN: [título]

context: [problema + constraints]

decision: ✓ [escolha]

rationale:
  + benefit 1
  + benefit 2
  - trade-off 1

alternatives considered:
  [option A]: ✓ [pros] | ✗ [cons]
  [option B]: ✓ [pros] | ✗ [cons]

consequences:
  + positive outcome
  - negative trade-off
  ? future dependency

status: [accepted | proposed | deprecated]
```

**Exemplo**:
```
# ADR-1: Use Flink SQL (not Spark) para event processing

context: 
  - Need real-time aggregations (< 5min latency)
  - Team has SQL expertise, new to Spark
  - Cost constraints ($500/mo budget)

decision: ✓ Apache Flink (managed via KDA)

rationale:
  + Sub-second latency native
  + SQL-first (lower learning curve)
  + AWS KDA = managed (no ops burden)
  - Cold start ~30s (acceptable)

alternatives considered:
  Spark Streaming: ✓ batch micro | ✗ higher latency, ops overhead
  Kafka Streams: ✓ embedded | ✗ JVM overhead, ops burden
  Lambda + Kinesis: ✓ simpler | ✗ can't aggregate across time

consequences:
  + Team productivity ↑ (SQL > Scala)
  + Ops simplified (managed KDA)
  - Vendor lock-in (AWS-specific)
  ? Future migrations harder

status: ✓ accepted (prod-ready)
```

---

## Template 9: Post-Mortem

```
INCIDENT: [título]

facts:
  • started: [time]
  • duration: [minutes]
  • affected: [services/teams]
  • severity: [P1/P2/P3]

timeline:
  [HH:MM] event happened
  [HH:MM] detected
  [HH:MM] war room opened
  [HH:MM] root cause found
  [HH:MM] fix deployed
  [HH:MM] resolved

root cause:
  [short technical explanation]

action items:
  • [action 1] → owner: [person] (ETA: date)
  • [action 2] → owner: [person] (ETA: date)

learnings:
  ✓ what went well
  ? what didn't
  ~ improvements for next time
```

**Exemplo**:
```
INCIDENT: Lambda credentials leak (AccessDenied x500)

facts:
  • started: Jun 5, 13:42 UTC
  • duration: 58 min
  • affected: flight-ingest pipeline
  • severity: P1 (data loss)

timeline:
  13:42 Lambda invoked, got AccessDenied (Secrets Manager)
  13:50 Monitoring alert sent
  13:58 On-call Slack message received
  14:05 Root cause: IAM policy missing
  14:15 Fix deployed (terraform apply)
  14:40 Data flow resumed

root cause:
  secretsmanager:GetSecretValue permission não foi adicionada na IAM policy.
  Review pré-deploy não caught esse gap.

action items:
  • Add IAM policy validation test (owner: alice@co, ETA: Jun 7)
  • Update deploy checklist: verify all IAM actions (owner: bob@co, ETA: Jun 6)
  • Increase alert sensitivity: first error = critical (owner: charlie@co, ETA: Jun 8)

learnings:
  ✓ Terraform plan caught structural issues
  ? IAM policy review foi skipped (need automation)
  ~ Future: use terraform policy-as-code (Sentinel/OPA)
```

---

*Response templates | caveman-style | June 5, 2026*
