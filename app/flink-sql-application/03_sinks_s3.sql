-- ============================================================================
-- FLINK SQL: SINK A - Agregação por País/Fase de Voo (S3)
-- ============================================================================
--
-- Agregação: por país e fase de voo, janela de 1 minuto
-- Destino: S3 Folder "opensky/flights-positions-1min/"
--
CREATE TABLE s3_positions_1min (
    window_start        TIMESTAMP(3),
    window_end          TIMESTAMP(3),
    origin_country      STRING,
    flight_phase        STRING,
    aircraft_count      BIGINT,
    avg_altitude_ft     DOUBLE,
    avg_velocity_kts    DOUBLE,
    avg_heading         DOUBLE,
    on_ground_count     BIGINT,
    dt                  STRING
) PARTITIONED BY (dt) WITH (
    'connector'                                = 'filesystem',
    'path'                                     = 's3://lakehouse-landing-331504768406/opensky/flights-positions-1min/',
    'format'                                   = 'parquet',
    'sink.partition-commit.delay'               = '1h',
    'sink.partition-commit.policy.kind'         = 'success-file',
    'sink.rolling-policy.rollover-interval'     = '60min',
    'sink.rolling-policy.check-interval'        = '10min'
);

INSERT INTO s3_positions_1min
SELECT
    TUMBLE_START(event_time, INTERVAL '1' MINUTE)   AS window_start,
    TUMBLE_END(event_time,   INTERVAL '1' MINUTE)   AS window_end,
    origin_country,
    flight_phase,
    COUNT(*)                                         AS aircraft_count,
    AVG(altitude_ft)                                 AS avg_altitude_ft,
    AVG(velocity_kts)                                AS avg_velocity_kts,
    AVG(heading)                                     AS avg_heading,
    SUM(CASE WHEN on_ground THEN 1 ELSE 0 END)       AS on_ground_count,
    DATE_FORMAT(TUMBLE_START(event_time, INTERVAL '1' MINUTE), 'yyyy-MM-dd-HH') AS dt
FROM enriched_flights
WHERE origin_country IS NOT NULL
  AND flight_phase IS NOT NULL
GROUP BY
    TUMBLE(event_time, INTERVAL '1' MINUTE),
    origin_country,
    flight_phase;

-- ============================================================================
-- SINK B - Distribuição por Faixa de Altitude (S3)
-- ============================================================================
--
-- Agregação: por fase de voo e tendência vertical, janela de 1 minuto
-- Destino: S3 Folder "opensky/flights-altitude-bands/"
--
CREATE TABLE s3_altitude_bands (
    window_start        TIMESTAMP(3),
    flight_phase        STRING,
    vertical_trend      STRING,
    aircraft_count      BIGINT,
    min_altitude_ft     DOUBLE,
    max_altitude_ft     DOUBLE,
    avg_altitude_ft     DOUBLE,
    velocity_stddev     DOUBLE,
    dt                  STRING
) PARTITIONED BY (dt) WITH (
    'connector'                                = 'filesystem',
    'path'                                     = 's3://lakehouse-landing-331504768406/opensky/flights-altitude-bands/',
    'format'                                   = 'parquet',
    'sink.partition-commit.delay'               = '1h',
    'sink.partition-commit.policy.kind'         = 'success-file',
    'sink.rolling-policy.rollover-interval'     = '60min',
    'sink.rolling-policy.check-interval'        = '10min'
);

INSERT INTO s3_altitude_bands
SELECT
    TUMBLE_START(event_time, INTERVAL '1' MINUTE) AS window_start,
    flight_phase,
    vertical_trend,
    COUNT(*)                                       AS aircraft_count,
    MIN(altitude_ft)                               AS min_altitude_ft,
    MAX(altitude_ft)                               AS max_altitude_ft,
    AVG(altitude_ft)                               AS avg_altitude_ft,
    STDDEV_SAMP(velocity_kts)                           AS velocity_stddev,
    DATE_FORMAT(TUMBLE_START(event_time, INTERVAL '1' MINUTE), 'yyyy-MM-dd-HH') AS dt
FROM enriched_flights
WHERE on_ground = FALSE
  AND altitude_ft IS NOT NULL
GROUP BY
    TUMBLE(event_time, INTERVAL '1' MINUTE),
    flight_phase,
    vertical_trend;

-- ============================================================================
-- SINK C - Mudanças de Fase de Voo (S3)
-- ============================================================================
--
-- Agregação: passthrough com filtro de mudança de fase, janela de 30 segundos
-- Destino: S3 Folder "opensky/flights-phase-changes/"
--
CREATE TABLE s3_phase_changes (
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
    dt                  STRING
) PARTITIONED BY (dt) WITH (
    'connector'                                = 'filesystem',
    'path'                                     = 's3://lakehouse-landing-331504768406/opensky/flights-phase-changes/',
    'format'                                   = 'parquet',
    'sink.partition-commit.delay'               = '1h',
    'sink.partition-commit.policy.kind'         = 'success-file',
    'sink.rolling-policy.rollover-interval'     = '60min',
    'sink.rolling-policy.check-interval'        = '10min'
);

INSERT INTO s3_phase_changes
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
    latitude,
    DATE_FORMAT(TUMBLE_START(event_time, INTERVAL '30' SECOND), 'yyyy-MM-dd-HH') AS dt
FROM enriched_flights
WHERE vertical_trend IN ('climbing', 'descending')
  AND ABS(vrate_fpm) > 500
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
-- SINK D - Passthrough Enriquecido (S3)
-- ============================================================================
--
-- Agregação: nenhuma (passthrough com dados enriquecidos)
-- Destino: S3 Folder "opensky/flights-enriched/"
--

CREATE TABLE s3_enriched (
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
    dt                  STRING
) PARTITIONED BY (dt) WITH (
    'connector'                                = 'filesystem',
    'path'                                     = 's3://lakehouse-landing-331504768406/opensky/flights-enriched/',
    'format'                                   = 'parquet',
    'sink.partition-commit.delay'               = '1h',
    'sink.partition-commit.policy.kind'         = 'success-file',
    'sink.rolling-policy.rollover-interval'     = '60min',
    'sink.rolling-policy.check-interval'        = '10min'
);

INSERT INTO s3_enriched
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
    spi,
    DATE_FORMAT(event_time, 'yyyy-MM-dd-HH') AS dt
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
-- Sink D (flights-enriched):
--   Rate: 1 evento por aeronave por ~10s (conforme atualização ADS-B)
--   Tamanho: ALTO (~50k-100k eventos/min globalmente)
--   Uso: histórico completo, data science, análise ad-hoc
--
-- =============================================================================
