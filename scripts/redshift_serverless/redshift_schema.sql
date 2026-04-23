-- ============================================================================
-- REDSHIFT: CONFIGURAÇÃO DE WAREHOUSE E TABELAS DE DESTINO
-- ============================================================================
--
-- Este arquivo contém:
-- 1. External schema para integração com Kinesis
-- 2. Materialized views para agregações em tempo real
-- 3. Fact tables para histórico
-- 4. Queries analíticas de exemplo
--
-- Pré-requisitos:
--   • Redshift cluster em execução
--   • Kinesis streams existindo (flights-positions-1min, etc)
--   • IAM role com permissão de leitura em Kinesis
--
-- ============================================================================
-- PASSO 1: EXTERNAL SCHEMA PARA KINESIS
-- ============================================================================
--
-- Permite que Redshift leia dados diretamente de streams Kinesis
-- sem necessidade de armazenar em S3 primeiro.
--

CREATE EXTERNAL SCHEMA IF NOT EXISTS kinesis_flights
FROM KINESIS 
IAM_ROLE 'arn:aws:iam::ACCOUNT_ID:role/RedshiftKinesisRole'
REGION 'us-east-1';

-- Verificar acesso:
-- SELECT * FROM kinesis_flights."flights-positions-1min" LIMIT 10;

-- ============================================================================
-- PASSO 2: MATERIALIZED VIEWS - AGREGAÇÕES EM TEMPO REAL
-- ============================================================================
--
-- MVs auto-refresh a cada 10 segundos (opcional: ajustar conforme SLA)
-- Ideal para dashboards que precisam de dados "quase em tempo real"
--

-- ============================================================================
-- MV 1: Posições por País - Densidade de Tráfego
-- ============================================================================
--
-- Atualização: a cada 10 segundos
-- Casos de uso:
--   • Mapa de heatmap global de tráfego
--   • Alertas de congestionamento por país
--   • Dashboard QuickSight
--
-- Schema:
--   • window_start: timestamp do início da janela (1 minuto)
--   • origin_country: código país ISO 2-letra
--   • flight_phase: ground, takeoff_landing, low, cruise, high_altitude
--   • aircraft_count: número de aeronaves nessa combinação
--   • avg_altitude_ft: altitude média em pés
--   • avg_velocity_kts: velocidade média em nós
--

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_positions_1min
AUTO REFRESH YES REFRESH EVERY 10 SECONDS AS
SELECT
    JSON_EXTRACT_PATH_TEXT(data, 'window_start')          AS window_start,
    JSON_EXTRACT_PATH_TEXT(data, 'window_end')            AS window_end,
    JSON_EXTRACT_PATH_TEXT(data, 'origin_country')        AS origin_country,
    JSON_EXTRACT_PATH_TEXT(data, 'flight_phase')          AS flight_phase,
    CAST(JSON_EXTRACT_PATH_TEXT(data, 'aircraft_count') AS INTEGER)
                                                          AS aircraft_count,
    CAST(JSON_EXTRACT_PATH_TEXT(data, 'avg_altitude_ft') AS DOUBLE PRECISION)
                                                          AS avg_altitude_ft,
    CAST(JSON_EXTRACT_PATH_TEXT(data, 'avg_velocity_kts') AS DOUBLE PRECISION)
                                                          AS avg_velocity_kts,
    CAST(JSON_EXTRACT_PATH_TEXT(data, 'avg_heading') AS DOUBLE PRECISION)
                                                          AS avg_heading,
    CAST(JSON_EXTRACT_PATH_TEXT(data, 'on_ground_count') AS INTEGER)
                                                          AS on_ground_count
FROM kinesis_flights."flights-positions-1min"
WHERE data IS NOT NULL;

-- Índice para performance
CREATE INDEX idx_mv_positions_1min_country ON mv_positions_1min (origin_country, window_start);

-- ============================================================================
-- MV 2: Distribuição de Altitude - Detecção de Anomalias
-- ============================================================================
--
-- Atualização: a cada 10 segundos
-- Casos de uso:
--   • Detectar aeronaves descendo quando deveriam estar em cruzeiro
--   • Monitorar distribuição por altitude
--   • Alertas de padrões anormais
--

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_altitude_bands
AUTO REFRESH YES REFRESH EVERY 10 SECONDS AS
SELECT
    JSON_EXTRACT_PATH_TEXT(data, 'window_start')          AS window_start,
    JSON_EXTRACT_PATH_TEXT(data, 'flight_phase')          AS flight_phase,
    JSON_EXTRACT_PATH_TEXT(data, 'vertical_trend')        AS vertical_trend,
    CAST(JSON_EXTRACT_PATH_TEXT(data, 'aircraft_count') AS INTEGER) AS aircraft_count,
    CAST(JSON_EXTRACT_PATH_TEXT(data, 'min_altitude_ft') AS DOUBLE PRECISION) AS min_altitude_ft,
    CAST(JSON_EXTRACT_PATH_TEXT(data, 'max_altitude_ft') AS DOUBLE PRECISION) AS max_altitude_ft,
    CAST(JSON_EXTRACT_PATH_TEXT(data, 'avg_altitude_ft') AS DOUBLE PRECISION) AS avg_altitude_ft,
    CAST(JSON_EXTRACT_PATH_TEXT(data, 'velocity_stddev') AS DOUBLE PRECISION) AS velocity_stddev
FROM kinesis_flights."flights-altitude-bands"
WHERE data IS NOT NULL;

-- ============================================================================
-- MV 3: Mudanças de Fase - Alertas Críticos
-- ============================================================================
--
-- Atualização: a cada 5 segundos (dados críticos)
-- Casos de uso:
--   • Alertas em tempo real de eventos críticos
--   • Subidas/descidas agressivas (>500 fpm)
--   • Detecção de anomalias comportamentais
--

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_phase_changes
AUTO REFRESH YES REFRESH EVERY 5 SECONDS AS
SELECT
    JSON_EXTRACT_PATH_TEXT(data, 'window_start')          AS window_start,
    JSON_EXTRACT_PATH_TEXT(data, 'icao24')                AS icao24,
    JSON_EXTRACT_PATH_TEXT(data, 'callsign')              AS callsign,
    JSON_EXTRACT_PATH_TEXT(data, 'origin_country')        AS origin_country,
    JSON_EXTRACT_PATH_TEXT(data, 'vertical_trend')        AS vertical_trend,
    CAST(JSON_EXTRACT_PATH_TEXT(data, 'vrate_fpm') AS DOUBLE PRECISION)
                                                          AS vrate_fpm,
    CAST(JSON_EXTRACT_PATH_TEXT(data, 'altitude_ft') AS DOUBLE PRECISION)
                                                          AS altitude_ft,
    JSON_EXTRACT_PATH_TEXT(data, 'speed_category')        AS speed_category,
    CAST(JSON_EXTRACT_PATH_TEXT(data, 'heading') AS DOUBLE PRECISION)
                                                          AS heading,
    CAST(JSON_EXTRACT_PATH_TEXT(data, 'longitude') AS DOUBLE PRECISION)
                                                          AS longitude,
    CAST(JSON_EXTRACT_PATH_TEXT(data, 'latitude') AS DOUBLE PRECISION)
                                                          AS latitude
FROM kinesis_flights."flights-phase-changes"
WHERE data IS NOT NULL;

-- ============================================================================
-- PASSO 3: FACT TABLES - HISTÓRICO PERSISTENTE
-- ============================================================================
--
-- Estas tabelas armazenam dados históricos carregados via Firehose + S3
-- Uso para análise histórica, compliance, data science
--

-- ============================================================================
-- FACT TABLE 1: Histórico de Posições (1 minuto agregado)
-- ============================================================================
--
-- Distribuição: por origin_country (melhor para queries por país)
-- Sort key: window_start (melhor para queries time-series)
-- Compressão: AZ64 (timestamp) + ZSTD (strings)
--
-- Carregamento:
--   • Via Firehose: streams Kinesis → S3 → Redshift COPY
--   • Frequência: a cada 10 minutos (batch de 10 janelas)
--   • Formato: Parquet ou JSON (via manifest)
--

CREATE TABLE IF NOT EXISTS fact_flight_positions (
    window_start        TIMESTAMP   NOT NULL ENCODE AZ64,
    window_end          TIMESTAMP   NOT NULL ENCODE AZ64,
    origin_country      VARCHAR(80)          ENCODE ZSTD,
    flight_phase        VARCHAR(20)          ENCODE BYTEDICT,
    aircraft_count      INT                  ENCODE LZO,
    avg_altitude_ft     FLOAT                ENCODE RAW,
    avg_velocity_kts    FLOAT                ENCODE RAW,
    avg_heading         FLOAT                ENCODE RAW,
    on_ground_count     INT                  ENCODE LZO,
    loaded_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP ENCODE AZ64
)
DISTKEY(origin_country)      -- Distribuir por país para join efficiency
SORTKEY(window_start)        -- Sort por timestamp para queries time-series
ENCODE ALL;                  -- Compressão automática para outras colunas

-- Índice para queries comuns
CREATE INDEX idx_fact_positions_country_time 
  ON fact_flight_positions (origin_country, window_start);

-- ============================================================================
-- FACT TABLE 2: Histórico de Distribuição por Altitude
-- ============================================================================
--

CREATE TABLE IF NOT EXISTS fact_altitude_bands (
    window_start        TIMESTAMP   NOT NULL ENCODE AZ64,
    flight_phase        VARCHAR(20)          ENCODE BYTEDICT,
    vertical_trend      VARCHAR(20)          ENCODE BYTEDICT,
    aircraft_count      INT                  ENCODE LZO,
    min_altitude_ft     FLOAT                ENCODE RAW,
    max_altitude_ft     FLOAT                ENCODE RAW,
    avg_altitude_ft     FLOAT                ENCODE RAW,
    velocity_stddev     FLOAT                ENCODE RAW,
    loaded_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP ENCODE AZ64
)
DISTKEY(flight_phase)
SORTKEY(window_start)
ENCODE ALL;

-- ============================================================================
-- FACT TABLE 3: Histórico Enriquecido (todas as aeronaves)
-- ============================================================================
--
-- ATENÇÃO: Esta tabela pode crescer MUITO (~50k-100k eventos/min)
-- Use particionamento (virtual) por data para performance
-- Considere usar compressed Parquet no S3 para cold storage
--

CREATE TABLE IF NOT EXISTS fact_enriched_flights (
    event_time          TIMESTAMP   NOT NULL ENCODE AZ64,
    icao24              VARCHAR(24) NOT NULL ENCODE ZSTD,
    callsign            VARCHAR(8)           ENCODE ZSTD,
    origin_country      VARCHAR(2)           ENCODE BYTEDICT,
    longitude           DOUBLE PRECISION     ENCODE RAW,
    latitude            DOUBLE PRECISION     ENCODE RAW,
    altitude_ft         DOUBLE PRECISION     ENCODE RAW,
    geo_altitude_ft     DOUBLE PRECISION     ENCODE RAW,
    velocity_kts        DOUBLE PRECISION     ENCODE RAW,
    heading             DOUBLE PRECISION     ENCODE RAW,
    vrate_fpm           DOUBLE PRECISION     ENCODE RAW,
    flight_phase        VARCHAR(20)          ENCODE BYTEDICT,
    vertical_trend      VARCHAR(20)          ENCODE BYTEDICT,
    speed_category      VARCHAR(20)          ENCODE BYTEDICT,
    on_ground           BOOLEAN              ENCODE RAW,
    squawk              VARCHAR(4)           ENCODE ZSTD,
    spi                 BOOLEAN              ENCODE RAW,
    loaded_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP ENCODE AZ64
)
DISTKEY(origin_country)  -- Ou considerar DISTSTYLE ALL se tabela < 5GB
SORTKEY(event_time, origin_country)
ENCODE ALL;

-- Índices para queries comuns
CREATE INDEX idx_fact_enriched_flights_icao 
  ON fact_enriched_flights (icao24, event_time);
CREATE INDEX idx_fact_enriched_flights_country 
  ON fact_enriched_flights (origin_country, event_time);

-- ============================================================================
-- PASSO 4: QUERIES ANALÍTICAS DE EXEMPLO
-- ============================================================================
--
-- Use estas queries como base para dashboards QuickSight
--

-- ============================================================================
-- QUERY 1: Tráfego por País nos últimos 10 minutos
-- ============================================================================
--

SELECT
    origin_country,
    SUM(aircraft_count)           AS total_aircraft,
    AVG(avg_altitude_ft)          AS avg_altitude_ft,
    AVG(avg_velocity_kts)         AS avg_velocity_kts,
    COUNT(DISTINCT flight_phase)  AS distinct_phases
FROM mv_positions_1min
WHERE window_start >= DATEADD(minute, -10, CURRENT_TIMESTAMP)
GROUP BY origin_country
ORDER BY total_aircraft DESC;

-- ============================================================================
-- QUERY 2: Distribuição de Altitude (anomalias)
-- ============================================================================
--
-- Detector de anomalias: aeronaves em cruise descendo rápido
--

SELECT
    window_start,
    flight_phase,
    vertical_trend,
    aircraft_count,
    avg_altitude_ft,
    velocity_stddev,
    CASE
        WHEN flight_phase = 'cruise' AND vertical_trend = 'descending'
             THEN 'ANOMALY_UNEXPECTED_DESCENT'
        WHEN flight_phase = 'low' AND vertical_trend = 'climbing'
             THEN 'NORMAL_CLIMB_TO_ALTITUDE'
        ELSE 'NORMAL'
    END AS anomaly_flag
FROM mv_altitude_bands
WHERE window_start >= DATEADD(minute, -30, CURRENT_TIMESTAMP)
ORDER BY window_start DESC;

-- ============================================================================
-- QUERY 3: Eventos de Mudança de Fase (alertas críticos)
-- ============================================================================
--

SELECT
    window_start,
    icao24,
    callsign,
    origin_country,
    vertical_trend,
    vrate_fpm,
    altitude_ft,
    speed_category,
    CASE
        WHEN vrate_fpm > 2000 THEN 'ALERT_AGGRESSIVE_CLIMB'
        WHEN vrate_fpm < -2000 THEN 'ALERT_AGGRESSIVE_DESCENT'
        WHEN ABS(vrate_fpm) > 500 THEN 'CAUTION_SIGNIFICANT_MOVE'
        ELSE 'INFO'
    END AS alert_level
FROM mv_phase_changes
WHERE window_start >= DATEADD(minute, -5, CURRENT_TIMESTAMP)
ORDER BY window_start DESC, ABS(vrate_fpm) DESC;

-- ============================================================================
-- QUERY 4: Análise Histórica - Tráfego Médio por Hora
-- ============================================================================
--
-- Use fact_flight_positions para análise histórica
--

SELECT
    DATE_TRUNC('hour', window_start)  AS hour,
    origin_country,
    AVG(aircraft_count)               AS avg_aircraft,
    MAX(aircraft_count)               AS peak_aircraft,
    AVG(avg_altitude_ft)              AS avg_altitude_ft,
    AVG(avg_velocity_kts)             AS avg_velocity_kts
FROM fact_flight_positions
WHERE window_start >= DATEADD(day, -7, CURRENT_TIMESTAMP)
GROUP BY DATE_TRUNC('hour', window_start), origin_country
ORDER BY hour DESC, origin_country;

-- ============================================================================
-- QUERY 5: Data Science - Padrões de Rota por Região
-- ============================================================================
--
-- Agregar dados enriquecidos para análise de clustering
--

SELECT
    EXTRACT(HOUR FROM event_time)  AS hour_of_day,
    origin_country,
    speed_category,
    flight_phase,
    COUNT(*)                       AS event_count,
    AVG(heading)                   AS avg_heading,
    AVG(altitude_ft)               AS avg_altitude_ft,
    STDDEV(altitude_ft)            AS altitude_stddev
FROM fact_enriched_flights
WHERE event_time >= DATEADD(day, -30, CURRENT_TIMESTAMP)
GROUP BY
    EXTRACT(HOUR FROM event_time),
    origin_country,
    speed_category,
    flight_phase
ORDER BY event_count DESC;

-- ============================================================================
-- PASSO 5: LIMPEZA E MANUTENÇÃO
-- ============================================================================
--

-- Comando para vacuum (limpeza) das fact tables
-- Executar regularmente (ex: diariamente às 2 AM)
--
-- VACUUM ANALYZE fact_flight_positions;
-- VACUUM ANALYZE fact_altitude_bands;
-- VACUUM ANALYZE fact_enriched_flights;

-- Deletar dados antigos (retenção de 90 dias)
--
-- DELETE FROM fact_flight_positions
-- WHERE window_start < DATEADD(day, -90, CURRENT_DATE);

-- ============================================================================
-- PASSO 6: MONITORAMENTO
-- ============================================================================
--

-- Ver tamanho das tables
SELECT
    schemaname,
    tablename,
    size_in_bytes / 1024 / 1024 / 1024 AS size_gb,
    tbl_rows
FROM svv_table_info
WHERE tablename IN ('fact_flight_positions', 'fact_altitude_bands', 'fact_enriched_flights')
ORDER BY size_gb DESC;

-- Ver status das MVs
SELECT
    schemaname,
    matviewname,
    definition
FROM pg_matviews
WHERE matviewname LIKE 'mv_%';

-- ============================================================================
