# 🏗️ Arquitetura AWS Streaming Flight Radar - Fluxo Corrigido

## ETAPA 1: INGESTÃO DE DADOS

```
OpenSky API 
    ↓
API Gateway → recebe requisições HTTP dos dados de voos
    ↓
Lambda-ingestão (lambda_flights_raw) → valida e formata eventos brutos
    ↓
kinesis_stream_flights ← Eventos brutos enfileirados
```

---

## ETAPA 2: STREAMING EM TEMPO REAL

### Fluxo 2A: RAW → S3 LANDING
```
kinesis_stream_flights (dados brutos)
    ↓
Kinesis Firehose 
    ↓
S3 Landing (armazenamento bruto - particionado por data/hora)
```

**Propósito**: Armazenar histórico completo de eventos brutos para auditoria e análise posterior

---

### Fluxo 2B: FLINK PROCESSING → REDSHIFT
```
kinesis_stream_flights (dados brutos)
    ↓
Flink (AWS KDA - Kinesis Data Analytics)
    ├─ Enriquecimento com dados referenciais (países, aeroportos)
    ├─ Transformações em tempo real
    └─ Agregações e janelas temporais
    ↓
kinesis_stream_flights_rt (dados enriquecidos)
    ↓
Redshift Warehouse (data warehouse em tempo real)
    ↓
QuickSight (dashboards BI em tempo real)
```

**Propósito**: Processamento em tempo real, transformação de dados e visualização com Flink + Redshift

---

## ETAPA 3: CATALOGAÇÃO & METADADOS

```
S3 Landing (dados brutos)
    ↓
AWS Glue Crawler (indexação automática a cada hora)
    ↓
AWS Glue Data Catalog (repositório de metadados)
    ├→ db_raw (tabelas brutas)
    ├→ db_trusted (dados validados/limpos)
    └→ db_business (dados prontos para negócio)
```

**Propósito**: Catalogar dados, criar estrutura de camadas (medallion architecture)

---

## ETAPA 4: ANALYTICS & VISUALIZAÇÃO

### Fluxo do EMR (Batch Processing)
```
S3 Landing (dados brutos)
    ↓
AWS Glue Data Catalog (metadados)
    ↓
EMR (2 instâncias Spark)
    ├─ Processamento distribuído
    ├─ Transformações complexas
    └─ Limpeza e validação de dados
    ↓
S3 Silver/Gold Layers
```

**Propósito**: Processamento em batch, transformações complexas, dados estruturados

---

### Fluxo do Redshift (Real-time Analytics)
```
kinesis_stream_flights_rt (dados enriquecidos do Flink)
    ↓
Redshift Warehouse (OLAP)
    ├─ Tabelas fato e dimensão
    ├─ Agregações em tempo real
    └─ Queries complexas
    ↓
QuickSight (BI & Visualizações)
```

**Propósito**: Analytics em tempo real, dashboards interativos

---

## 📊 FLUXO COMPLETO RESUMIDO

```
┌─────────────────────────────────────────────────────────────────┐
│                        INGESTÃO (ETAPA 1)                        │
│  OpenSky API → API Gateway → Lambda-ingestão → Kinesis Stream  │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│              STREAMING EM TEMPO REAL (ETAPA 2)                   │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Fluxo 2A: RAW → S3                                       │   │
│  │ Kinesis → Firehose → S3 Landing                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Fluxo 2B: FLINK → REDSHIFT                              │   │
│  │ Kinesis → Flink (KDA) → Kinesis RT → Redshift → BI      │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│             CATALOGAÇÃO & METADADOS (ETAPA 3)                    │
│     S3 Landing → Glue Crawler → Data Catalog (3 camadas)        │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│            ANALYTICS & VISUALIZAÇÃO (ETAPA 4)                    │
│                                                                  │
│  Batch: EMR → S3 Silver/Gold                                    │
│  Real-time: Redshift → QuickSight                               │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔌 MÓDULOS TERRAFORM IMPLEMENTADOS

| Módulo | Descrição | Função |
|--------|-----------|--------|
| `kinesis_stream_flights` | Streams Kinesis (raw + rt) | Ingestão e distribuição de eventos |
| `kinesis_firehose_flights` | Firehose para S3 | Armazenamento de dados brutos |
| `kda_flights` | **NOVO**: Flink/KDA | Processamento e enriquecimento em tempo real |
| `lambda_flights_raw` | Lambda de ingestão | Validação e formatação de dados brutos |
| `lambda_flights_enriched` | Lambda enriquecida | Transformações (se usado) |
| `iam` | Roles e políticas | Permissões de acesso |
| `cloudwatch_monitoring` | Logs e métricas | Observabilidade |

---

## 🎯 CARACTERÍSTICAS DO NOVO FLUXO

✅ **Escalável**: Kinesis + Flink + EMR podem processar milhões de eventos/segundo  
✅ **Tempo Real**: Flink processa e enriquece dados instantaneamente → Redshift → BI  
✅ **Histórico**: S3 Landing armazena todos os dados brutos para análise posterior  
✅ **Multi-camada**: Medallion architecture (raw → trusted → business)  
✅ **Monitoramento**: CloudWatch Logs em cada etapa (Flink, Firehose, etc)  
✅ **Recuperável**: Snapshots do Flink para disaster recovery  

---

## 🚀 PRÓXIMOS PASSOS

1. ✅ Criar módulo `kda_flights` (Apache Flink)
2. ⏳ Implementar aplicação Flink (arquivo JAR com lógica de transformação)
3. ⏳ Configurar Redshift com tabelas fact/dimension
4. ⏳ Integrar Redshift Spectrum para querying de S3 via Glue Catalog
5. ⏳ Conectar QuickSight ao Redshift para dashboards
6. ⏳ Implementar alertas CloudWatch para anomalias
