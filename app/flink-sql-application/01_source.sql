-- ============================================================================
-- FLINK SQL: SOURCE - Ingestão de dados ADS-B do OpenSky via Kinesis
-- ============================================================================
-- 
-- Este script define a tabela source que consome eventos brutos de voos
-- do Kinesis Stream "flights-raw". Cada evento é um vetor de estado ADS-B
-- contendo informações de posição, velocidade e altitude de uma aeronave.
--
-- Watermark: 30 segundos para tolerar eventos fora de ordem (múltiplos sensores)
--

-- Source table: Kinesis Stream com dados brutos ADS-B
CREATE TABLE state_vectors_source (
    icao24              STRING NOT NULL,           -- Identificador único da aeronave (ICAO)
    callsign            STRING,                    -- Callsign (ex: "TAP1234")
    origin_country      STRING,                    -- País de origem (ISO 2-letter code)
    time_position       STRING,                    -- ISO 8601 timestamp da posição
    last_contact        STRING,                    -- ISO 8601 timestamp do último contato
    longitude           DOUBLE,                    -- Longitude em graus (-180 a 180)
    latitude            DOUBLE,                    -- Latitude em graus (-90 a 90)
    altitude            DOUBLE,                    -- Altitude em metros (pode ser null)
    on_ground           BOOLEAN,                   -- Indica se aeronave está no solo
    velocity            DOUBLE,                    -- Velocidade em m/s (pode ser null)
    heading             DOUBLE,                    -- Direção em graus (0-360)
    vertical_rate       DOUBLE,                    -- Taxa vertical em m/s (positivo=subindo)
    geo_altitude        DOUBLE,                    -- Altitude geométrica em metros
    squawk              STRING,                    -- Código squawk transponder
    spi                 BOOLEAN,                   -- Special Position Identification flag
    position_source     INT,                       -- Fonte de posição (0=ADS-B, 1=surface, 2=radar, etc)
    
    -- Metadados Kinesis
    event_time          TIMESTAMP(3) METADATA FROM 'timestamp',  -- Timestamp do evento Kinesis
    
    -- Watermark: tolera 30s de atraso para eventos fora de ordem
    WATERMARK FOR event_time AS event_time - INTERVAL '30' SECOND
) WITH (
    'connector'                 = 'kinesis',
    'stream'                    = 'flights-raw',
    'aws.region'                = 'us-east-1',
    'scan.stream.initpos'       = 'LATEST',          -- Inicia a partir dos eventos mais recentes
    'format'                    = 'json',
    'json.ignore-parse-errors'  = 'true',            -- Ignora JSON malformado
    'json.fail-on-missing-field'= 'false'            -- Permite campos faltantes (nulls)
);

-- =============================================================================
-- NOTAS TÉCNICAS
-- =============================================================================
--
-- 1. WATERMARK:
--    - 30s permite que eventos atrasados 30s ou menos sejam inclusos
--    - Útil pois múltiplos sensores ADS-B reportam a mesma aeronave com latências
--    - Após 30s, janelas temporais fecham e novos eventos são descartados
--
-- 2. TIMESTAMP HANDLING:
--    - event_time vem do metadata Kinesis (quando chegou no stream)
--    - time_position é string ISO 8601 que será parseado na VIEW enriquecida
--
-- 3. VALIDAÇÕES:
--    - icao24 é NOT NULL (identificador obrigatório)
--    - longitude/latitude tem validação na VIEW (entre -180/180 e -90/90)
--    - on_ground é BOOLEAN para fase de voo
--
-- 4. DADOS NULL:
--    - altitude, velocity podem ser NULL para aeronaves em solo
--    - vertical_rate é NULL durante voo horizontal
--    - callsign pode ser vazio ou NULL
--
-- =============================================================================
