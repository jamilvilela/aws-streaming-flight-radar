-- ============================================================================
-- FLINK SQL: SINK A - Agregação por País/Fase de Voo (1 minuto)
-- ============================================================================
--
-- Agregação: por país e fase de voo, janela de 1 minuto
-- Casos de uso:
--   - Mapa de densidade de tráfego em tempo real (QuickSight)
--   - Alertas de congestionamento por região
--   - Análise de distribuição de fase de voo por país
--
-- Destino: Kinesis Stream "flights-positions-1min"
-- Frequência: evento a cada minuto (TUMBLE window)
--

CREATE TABLE kinesis_positions_1min (
    window_start        TIMESTAMP(3),
    window_end          TIMESTAMP(3),
    origin_country      STRING,
    flight_phase        STRING,
    aircraft_count      BIGINT,
    avg_altitude_ft     DOUBLE,
    avg_velocity_kts    DOUBLE,
    avg_heading         DOUBLE,
    on_ground_count     BIGINT,
    PRIMARY KEY (window_start, origin_country, flight_phase) NOT ENFORCED
) WITH (
    'connector'                = 'kinesis',
    'stream.arn'               = 'arn:aws:kinesis:us-east-1:331504768406:stream/flight-radar-stream-flights-rt',
    'aws.region'               = 'us-east-1',
    'format'                   = 'json'
);

INSERT INTO kinesis_positions_1min
SELECT
    TUMBLE_START(event_time, INTERVAL '1' MINUTE)   AS window_start,
    TUMBLE_END(event_time,   INTERVAL '1' MINUTE)   AS window_end,
    origin_country,
    flight_phase,
    COUNT(*)                                         AS aircraft_count,
    AVG(altitude_ft)                                 AS avg_altitude_ft,
    AVG(velocity_kts)                                AS avg_velocity_kts,
    AVG(heading)                                     AS avg_heading,
    SUM(CASE WHEN on_ground THEN 1 ELSE 0 END)       AS on_ground_count
FROM enriched_flights
WHERE origin_country IS NOT NULL
  AND flight_phase IS NOT NULL
GROUP BY
    TUMBLE(event_time, INTERVAL '1' MINUTE),
    origin_country,
    flight_phase;

-- ============================================================================
-- SINK B - Distribuição por Faixa de Altitude (1 minuto)
-- ============================================================================
--
-- Agregação: por fase de voo e tendência vertical, janela de 1 minuto
-- Casos de uso:
--   - Detectar anomalias de altitude (aeronaves descendo quando deveriam estar em cruzeiro)
--   - Monitorar distribuição de aeronaves por altitude
--   - Análise de padrões de subida/descida
--
-- Filtro: apenas voos em ar (on_ground = false)
-- Destino: Kinesis Stream "flights-altitude-bands"
--

CREATE TABLE kinesis_altitude_bands (
    window_start        TIMESTAMP(3),
    flight_phase        STRING,
    vertical_trend      STRING,
    aircraft_count      BIGINT,
    min_altitude_ft     DOUBLE,
    max_altitude_ft     DOUBLE,
    avg_altitude_ft     DOUBLE,
    velocity_stddev     DOUBLE,
    PRIMARY KEY (window_start, flight_phase, vertical_trend) NOT ENFORCED
) WITH (
    'connector'                = 'kinesis',
    'stream.arn'               = 'arn:aws:kinesis:us-east-1:331504768406:stream/flight-radar-stream-flights-rt',
    'aws.region'               = 'us-east-1',
    'format'                   = 'json'
);

INSERT INTO kinesis_altitude_bands
SELECT
    TUMBLE_START(event_time, INTERVAL '1' MINUTE) AS window_start,
    flight_phase,
    vertical_trend,
    COUNT(*)                                       AS aircraft_count,
    MIN(altitude_ft)                               AS min_altitude_ft,
    MAX(altitude_ft)                               AS max_altitude_ft,
    AVG(altitude_ft)                               AS avg_altitude_ft,
    STDDEV_SAMP(velocity_kts)                           AS velocity_stddev
FROM enriched_flights
WHERE on_ground = FALSE
  AND altitude_ft IS NOT NULL
GROUP BY
    TUMBLE(event_time, INTERVAL '1' MINUTE),
    flight_phase,
    vertical_trend;

-- ============================================================================
-- SINK C - Mudanças de Fase de Voo (30 segundos)
-- ============================================================================
--
-- Agregação: passthrough com filtro de mudança de fase, janela de 30 segundos
-- Casos de uso:
--   - Alertas em tempo real de mudanças de fase críticas
--   - Detectar subidas/descidas agressivas (>500 fpm)
--   - Monitorar transições takeoff → climb → cruise
--
-- Filtro: 
--   - Apenas aeronaves em movimento vertical (climbing/descending)
--   - Taxa vertical > 500 fpm (evita variações insignificantes)
--   - Apenas em ar (on_ground = false)
--
-- Destino: Kinesis Stream "flights-phase-changes"
--

CREATE TABLE kinesis_phase_changes (
    window_start        TIMESTAMP(3),
    icao24              STRING,
    callsign            STRING,
    origin_country      STRING,
    vertical_trend      STRING,
    vrate_fpm           DOUBLE,
    altitude_ft         DOUBLE,
    speed_category      STRING,
    heading             DOUBLE,
    longitude           DOUBLE,
    latitude            DOUBLE,
    PRIMARY KEY (window_start, icao24) NOT ENFORCED
) WITH (
    'connector'                = 'kinesis',
    'stream.arn'               = 'arn:aws:kinesis:us-east-1:331504768406:stream/flight-radar-stream-flights-rt',
    'aws.region'               = 'us-east-1',
    'format'                   = 'json'
);

INSERT INTO kinesis_phase_changes
SELECT
    TUMBLE_START(event_time, INTERVAL '30' SECOND) AS window_start,
    icao24,
    callsign,
    origin_country,
    vertical_trend,
    vrate_fpm,
    altitude_ft,
    speed_category,
    heading,
    longitude,
    latitude
FROM enriched_flights
WHERE vertical_trend IN ('climbing', 'descending')
  AND ABS(vrate_fpm) > 500      -- Filtra variações insignificantes (< 500 fpm)
  AND on_ground = FALSE
GROUP BY
    TUMBLE(event_time, INTERVAL '30' SECOND),
    icao24,
    callsign,
    origin_country,
    vertical_trend,
    vrate_fpm,
    altitude_ft,
    speed_category,
    heading,
    longitude,
    latitude;

-- ============================================================================
-- SINK D - Passthrough Enriquecido (Todas as Aeronaves)
-- ============================================================================
--
-- Agregação: nenhuma (passthrough com dados enriquecidos)
-- Casos de uso:
--   - Base para data science: clustering de rotas, padrões de squawk
--   - Histórico completo em S3 via Firehose
--   - Treinamento de modelos de detecção de anomalias
--
-- Nota: SEM watermarking/windowing, apenas enriquecimento
-- Destino: Kinesis Stream "flights-enriched-raw"
--

CREATE TABLE kinesis_enriched_raw (
    event_time          TIMESTAMP(3),
    icao24              STRING,
    callsign            STRING,
    origin_country      STRING,
    longitude           DOUBLE,
    latitude            DOUBLE,
    altitude_ft         DOUBLE,
    geo_altitude_ft     DOUBLE,
    velocity_kts        DOUBLE,
    heading             DOUBLE,
    vrate_fpm           DOUBLE,
    flight_phase        STRING,
    vertical_trend      STRING,
    speed_category      STRING,
    on_ground           BOOLEAN,
    squawk              STRING,
    spi                 BOOLEAN,
    PRIMARY KEY (icao24) NOT ENFORCED
) WITH (
    'connector'                = 'kinesis',
    'stream.arn'               = 'arn:aws:kinesis:us-east-1:331504768406:stream/flight-radar-stream-flights-rt',
    'aws.region'               = 'us-east-1',
    'format'                   = 'json'
);

INSERT INTO kinesis_enriched_raw
SELECT
    event_time,
    icao24,
    callsign,
    origin_country,
    longitude,
    latitude,
    altitude_ft,
    geo_altitude_ft,
    velocity_kts,
    heading,
    vrate_fpm,
    flight_phase,
    vertical_trend,
    speed_category,
    on_ground,
    squawk,
    spi
FROM enriched_flights;

-- =============================================================================
-- RESUMO DOS SINKS
-- =============================================================================
--
-- Sink A (flights-positions-1min):
--   Rate: 1 evento/min por país/fase
--   Tamanho: baixo (~50-100 eventos/min globalmente)
--   Uso: dashboard tempo real de densidade
--
-- Sink B (flights-altitude-bands):
--   Rate: 1 evento/min por combinação única
--   Tamanho: médio (~500-1000 eventos/min)
--   Uso: detecção de anomalias de altitude
--
-- Sink C (flights-phase-changes):
--   Rate: variável (somente mudanças significativas)
--   Tamanho: baixo (~100-500 eventos/min em horário de pico)
--   Uso: alertas em tempo real de eventos críticos
--
-- Sink D (flights-enriched-raw):
--   Rate: 1 evento por aeronave por ~10s (conforme atualização ADS-B)
--   Tamanho: ALTO (~50k-100k eventos/min globalmente)
--   Uso: histórico completo, data science, análise ad-hoc
--
-- =============================================================================
