# 📊 Estrutura SQL: Resumo Executivo

## Implementação Concluída: Flink SQL + Redshift

Implementação completa de uma pipeline de streaming de dados ADS-B (OpenSky) com **Flink SQL** em 3 camadas (ingestão → transformação → múltiplos sinks).

---

## 📁 Arquivos Criados

### 1. **`app/flink-sql-application/`** - Aplicação Flink SQL

```
├── README.md                  # Visão geral da pipeline
├── QUICK_START.md             # Guia rápido de início
├── deploy_flink_sql.sh        # Script de deployment e monitoramento
├── 01_source.sql              # TABLE SOURCE (Kinesis input)
├── 02_enriched_view.sql       # VIEW com transformações
└── 03_sinks_kinesis.sql       # 4 Sinks de saída
```

### 2. **`infra/redshift_schema.sql`** - Warehouse Redshift

- External schema para Kinesis
- 3 Materialized Views (auto-refresh)
- 3 Fact tables (histórico)
- 5 Queries analíticas de exemplo

---

## 🔄 Fluxo Arquitetural

```
┌─────────────────────────────────────────────────────────────────┐
│                         INGESTÃO                                │
├─────────────────────────────────────────────────────────────────┤
│ OpenSky API → Lambda-ingestão → Kinesis (flights-raw)          │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                      FLINK SQL PROCESSING                       │
├─────────────────────────────────────────────────────────────────┤
│ Table SOURCE (state_vectors_source)                            │
│        ↓                                                         │
│ Conversões de unidades + Classificações (enriched_flights VIEW)│
│        ↓                                                         │
│ 4 TRANSFORMAÇÕES PARALELAS:                                    │
│  ├─ Sink A: positions-1min (país/fase, 1min)                   │
│  ├─ Sink B: altitude-bands (fase/tendência, 1min)              │
│  ├─ Sink C: phase-changes (mudanças >500 fpm, 30s)             │
│  └─ Sink D: enriched-raw (passthrough enriquecido)             │
└─────────────────────────────────────────────────────────────────┘
             ↓↓↓↓
┌─────────────────────────────────────────────────────────────────┐
│                     REDSHIFT WAREHOUSE                          │
├─────────────────────────────────────────────────────────────────┤
│ MVs (Materialized Views) - auto-refresh 10s                    │
│ ├─ mv_positions_1min → heatmap tempo real                      │
│ ├─ mv_altitude_bands → distribuição altitude                  │
│ └─ mv_phase_changes → alertas críticos                        │
│                                                                 │
│ Fact Tables - histórico persistente                            │
│ ├─ fact_flight_positions → agregado 1min                       │
│ ├─ fact_altitude_bands → distribuição histórica               │
│ └─ fact_enriched_flights → todas as aeronaves                 │
└─────────────────────────────────────────────────────────────────┘
             ↓
┌─────────────────────────────────────────────────────────────────┐
│                    QUICKSIGHT DASHBOARDS                        │
├─────────────────────────────────────────────────────────────────┤
│ • Mapa de heatmap global (tráfego por país/região)            │
│ • Alertas de congestionamento em tempo real                   │
│ • Análise de tendências (última semana/mês)                   │
│ • Detecção de anomalias de altitude                           │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🎯 Casos de Uso por Sink

### **Sink A: `flights-positions-1min`**
- **Agregação**: país + fase de voo, janela de 1 minuto
- **Throughput**: ~100-300 eventos/min
- **Uso**: Mapa de densidade de tráfego em tempo real
- **Dashboard**: Heatmap global, alertas de congestionamento

### **Sink B: `flights-altitude-bands`**
- **Agregação**: fase de voo + tendência vertical, janela de 1 minuto
- **Throughput**: ~500-1000 eventos/min
- **Uso**: Detecção de anomalias de altitude
- **Alertas**: Aeronave em cruise descendo inesperadamente

### **Sink C: `flights-phase-changes`**
- **Filtro**: Apenas mudanças significativas (>500 fpm)
- **Janela**: 30 segundos
- **Throughput**: ~100-500 eventos/min (variável)
- **Uso**: Alertas críticos de eventos de interesse
- **Exemplos**: Subida agressiva (>2000 fpm), descida rápida (<-2000 fpm)

### **Sink D: `flights-enriched-raw`**
- **Tipo**: Passthrough enriquecido (sem agregação)
- **Throughput**: ~50-100k eventos/min (HIGH)
- **Uso**: Base para data science e histórico completo
- **Aplicações**: Clustering de rotas, análise de padrões, treinamento ML

---

## 📝 Transformações SQL Principais

### Conversão de Unidades
```sql
altitude_ft = altitude * 3.28084           -- metros → pés
velocity_kts = velocity * 1.94384          -- m/s → knots
vrate_fpm = vertical_rate * 196.85         -- m/s → feet per minute
```

### Classificações Analíticas
```sql
flight_phase = CASE
    WHEN on_ground = TRUE THEN 'ground'
    WHEN altitude_ft < 1000 THEN 'takeoff_landing'
    WHEN altitude_ft < 10000 THEN 'low'
    WHEN altitude_ft < 35000 THEN 'cruise'
    ELSE 'high_altitude'
END

vertical_trend = CASE
    WHEN vertical_rate > 2.0 THEN 'climbing'
    WHEN vertical_rate < -2.0 THEN 'descending'
    ELSE 'level'
END
```

---

## 🚀 Como Usar

### 1. **Deploy Inicial**
```bash
# Criar Kinesis streams e iniciar Flink
bash app/flink-sql-application/deploy_flink_sql.sh start
```

### 2. **Monitorar Status**
```bash
bash app/flink-sql-application/deploy_flink_sql.sh status
bash app/flink-sql-application/deploy_flink_sql.sh logs
```

### 3. **Testar com Dados**
```bash
bash app/flink-sql-application/deploy_flink_sql.sh test
```

### 4. **Configurar Redshift**
```bash
# Execute o arquivo de schema Redshift
psql -h <redshift-endpoint> -U <admin> -d <database> -f infra/redshift_schema.sql
```

### 5. **Criar Dashboards QuickSight**
Conecte QuickSight ao Redshift e use as MVs como fonte de dados

---

## 📊 Performance Esperada

| Métrica | Valor |
|---------|-------|
| **Throughput entrada** | 50k-100k evt/min |
| **Sink A (aggregated)** | 100-300 evt/min |
| **Sink B (altitude)** | 500-1k evt/min |
| **Sink C (alerts)** | 100-500 evt/min |
| **Sink D (all)** | 50k-100k evt/min |
| **Latência e2e** | 500ms - 2s |
| **Window lag** | até 1 minuto (TUMBLE) |
| **DPUs necessários** | 4 (100k evt/min) |
| **Custo/dia** | ~$48 (4 DPUs × $0.50/h) |

---

## 🔧 Configuração Recomendada (terraform.tfvars)

```hcl
# Flink
flink_jar_bucket_arn = "arn:aws:s3:::flight-radar-data"
flink_jar_key = "flink-jars/flights-flink-app-1.0.jar"
input_parallelism = 4

# Reference data
reference_data_bucket_arn = "arn:aws:s3:::flight-radar-data"
reference_data_key = "reference-data/flights-reference-data.json"

# Checkpointing
checkpoint_interval = 60000         # 60 segundos
min_pause_between_checkpoints = 5000 # 5 segundos

# Watermarking
watermark_interval = 30000  # 30 segundos (tolera atrasos)
```

---

## 📚 Arquivos de Referência

| Arquivo | Descrição |
|---------|-----------|
| `01_source.sql` | Lê dados brutos do Kinesis |
| `02_enriched_view.sql` | Enriquece com conversões e classificações |
| `03_sinks_kinesis.sql` | Define 4 sinks de saída com transformações |
| `redshift_schema.sql` | Cria MVs e fact tables no Redshift |
| `QUICK_START.md` | Guia de início rápido (arquitetura visual) |
| `deploy_flink_sql.sh` | Automação de deploy e monitoramento |

---

## ✅ Checklist: Próximos Passos

- [ ] Deploy Terraform (KDA + Kinesis streams)
- [ ] Upload arquivo JAR em S3 (se usar Java) ou usar SQL diretamente
- [ ] Executar scripts SQL em ordem (01 → 02 → 03)
- [ ] Validar dados nos 4 sinks via CloudWatch Logs
- [ ] Criar Redshift cluster
- [ ] Executar `redshift_schema.sql`
- [ ] Conectar QuickSight ao Redshift
- [ ] Criar dashboards (heatmap, alertas, tendências)
- [ ] Implementar alertas CloudWatch
- [ ] Configurar auto-scaling (KDA)
- [ ] Estabelecer monitoramento contínuo

---

## 🎓 Conceitos-Chave

### Watermarking (30s)
Tolera eventos atrasados até 30 segundos. Essencial pois múltiplos sensores ADS-B reportam a mesma aeronave com latências diferentes.

### TUMBLE Windows
Janelas não-sobrepostas (1 minuto). Cada evento aparece em exatamente uma janela. Ideal para agregações determinísticas.

### Exactly-Once Semantics
Flink garante processamento exatamente uma vez via checkpointing. Perfeito para dados financeiros e críticos.

### Redshift Materialized Views
Auto-refresh a cada 10s. Ideal para dashboards que precisam de dados quase em tempo real, mas sem latência de streaming puro.

---

## 🐛 Troubleshooting

**Problema**: Nenhum evento nos sinks
- Verificar se Kinesis tem dados: `aws kinesis describe-stream --stream-name flights-raw`
- Ver logs: `aws logs tail /aws/kinesisanalytics/flight-radar-kda-flights --follow`
- Testar permissões IAM

**Problema**: Lag crescente nos sinks
- Aumentar `input_parallelism` (mais DPUs)
- Verificar se há backpressure
- Validar network connectivity

**Problema**: Custos mais altos que esperado
- Monitorar DPU usage em tempo real
- Ajustar auto-scaling thresholds
- Considerar batch processing para dados históricos (EMR)

---

## 📖 Referências

- [AWS KDA V2 SQL](https://docs.aws.amazon.com/kinesis/latest/dev/creating-sql-application.html)
- [Apache Flink SQL Cookbook](https://github.com/ververica/flink-sql-cookbook)
- [Redshift Materialized Views](https://docs.aws.amazon.com/redshift/latest/dg/materialized-view-overview.html)
- [QuickSight Best Practices](https://docs.aws.amazon.com/quicksight/latest/user/best-practices.html)

---

**Última Atualização**: Abril 19, 2026  
**Versão Flink**: 1.19  
**Redshift Spectrum**: Habilitado (opcional)  
**QuickSight**: SPICE Mode (recomendado)
