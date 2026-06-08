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
    icao24              STRING,                    -- Identificador único da aeronave (ICAO)
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
    
    -- Timestamp de ingestão (adicionado pelo Lambda)
    ingested_at         STRING,                     -- ISO 8601 quando o Lambda enviou ao Kinesis

    -- Event time derivado do ingested_at (evita METADATA do Kinesis connector que causa
    -- mismatch de arity: RowDataSerializer espera 17 campos mas JSON produz 16)
    event_time          AS TO_TIMESTAMP(REPLACE(SUBSTRING(ingested_at, 1, 19), 'T', ' ')),

    -- Watermark: tolera 30s de atraso para eventos fora de ordem
    WATERMARK FOR event_time AS event_time - INTERVAL '30' SECOND
) WITH (
    'connector'                 = 'kinesis',
    'stream.arn'                = '${KINESIS_STREAM_ARN}',
    'aws.region'                = '${AWS_REGION}',
    'source.init.position'      = 'LATEST',
    'format'                    = 'json',
    'json.ignore-parse-errors'  = 'true',
    'json.fail-on-missing-field'= 'false'
);

-- =============================================================================
-- NOTAS TÉCNICAS
-- =============================================================================
--
-- 1. WATERMARK vs CURRENT_TIMESTAMP:
--    ✓ WATERMARK FOR event_time AS event_time - INTERVAL '30' SECOND
--      - Usa o timestamp DO EVENTO (quando saiu da aeronave/sensor)
--      - Permite out-of-order events até 30s
--      - Agrupa eventos relacionados da mesma aeronave
--      - time_position é a "verdade" dos dados (quando o voo realmente aconteceu)
--    
--    ✗ CURRENT_TIMESTAMP AS event_time
--      - Usa o timestamp DO PROCESSAMENTO (quando Flink recebeu)
--      - Perderia a ordem real dos eventos
--      - Janelas agrupariam por "quando Flink processou", não "quando voo aconteceu"
--      - Exemplo: 2 sensores reportam mesma aeronave → timestamps diferentes no Flink
--        mesmo que tenham acontecido no mesmo segundo
--    
--    MOTIVO PRÁTICO:
--    - ADS-B: múltiplos receptores geográficos reportam mesma aeronave
--    - Latências diferentes por receptor (rede, processamento)
--    - event_time (Kinesis metadata) = quando Kinesis recebeu a mensagem
--    - Watermark 30s = tolera receptores reportando com até 30s de atraso
--    - Resultado: agrupa corretamente eventos que REALMENTE aconteceram junto
--
-- 2. EVENT TIME vs PROCESSING TIME:
--    - Event Time: quando o evento aconteceu (time_position do ADS-B)
--    - Ingestion Time: quando Kinesis recebeu (event_time metadata)
--    - Processing Time: quando Flink processou (CURRENT_TIMESTAMP)
--    
--    Para análise de tráfego aéreo, Event Time é essencial porque:
--    - Preserva causalidade (eventos na ordem que realmente aconteceram)
--    - Permite correlação correta entre múltiplas fontes
--    - Janelas de agregação significam "neste momento no mundo real"
--
-- 3. TIMESTAMP HANDLING:
--    - event_time vem do metadata Kinesis (quando chegou no stream)
--    - time_position é string ISO 8601 que será parseado na VIEW enriquecida
--
-- 4. VALIDAÇÕES:
--    - icao24 é NOT NULL (identificador obrigatório)
--    - longitude/latitude tem validação na VIEW (entre -180/180 e -90/90)
--    - on_ground é BOOLEAN para fase de voo
--
-- 5. DADOS NULL:
--    - altitude, velocity podem ser NULL para aeronaves em solo
--    - vertical_rate é NULL durante voo horizontal
--    - callsign pode ser vazio ou NULL
--
-- =============================================================================
