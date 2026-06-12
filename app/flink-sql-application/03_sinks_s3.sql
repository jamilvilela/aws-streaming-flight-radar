-- ============================================================================
-- FLINK SQL: SINK - Raw passthrough para S3 (teste de conexão S3)
-- ============================================================================
--
-- Single S3 passthrough sink para validar o connector filesystem com o
-- bucket lakehouse-landing. Se este sink falhar com o mesmo erro
-- "Stream closed" do S3RecoverableFsDataOutputStream, confirma que o
-- connector filesystem+S3 tem incompatibilidade com o ambiente KDA.
--
-- Estratégia incremental:
--   V19: Kinesis sink ✓ (pipeline base funciona)
--   V20: S3 passthrough sink (este - testar connector filesystem)
--   V21+: Adicionar sinks windowed (A/B/C) se V20 for estável
-- ============================================================================

CREATE TABLE s3_enriched_raw (
    icao24              STRING,
    callsign            STRING,
    origin_country      STRING,
    time_position       STRING,
    last_contact        STRING,
    longitude           DOUBLE,
    latitude            DOUBLE,
    altitude            DOUBLE,
    on_ground           BOOLEAN,
    velocity            DOUBLE,
    heading             DOUBLE,
    vertical_rate       DOUBLE,
    geo_altitude        DOUBLE,
    squawk              STRING,
    spi                 BOOLEAN,
    position_source     INT,
    ingested_at         STRING,
    event_time          TIMESTAMP(3),
    dt                  STRING
) PARTITIONED BY (dt) WITH (
    'connector'                                = 'filesystem',
    'path'                                     = 's3://lakehouse-landing-331504768406/opensky/flights-enriched-raw/',
    'format'                                   = 'json',
    'sink.partition-commit.delay'               = '1min',
    'sink.partition-commit.policy.kind'         = 'success-file',
    'sink.rolling-policy.rollover-interval'     = '10min',
    'sink.rolling-policy.inactivity-interval'   = '5min',
    'sink.rolling-policy.check-interval'        = '1min'
);

INSERT INTO s3_enriched_raw
SELECT
    icao24,
    callsign,
    origin_country,
    time_position,
    last_contact,
    longitude,
    latitude,
    altitude,
    on_ground,
    velocity,
    heading,
    vertical_rate,
    geo_altitude,
    squawk,
    spi,
    position_source,
    ingested_at,
    event_time - INTERVAL '3' HOUR    AS event_time,
    DATE_FORMAT(event_time - INTERVAL '3' HOUR, 'yyyy-MM-dd-HH') AS dt
FROM state_vectors_source;
