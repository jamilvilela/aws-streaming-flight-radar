-- ============================================================================
-- FLINK SQL: VIEW ENRIQUECIDA - Conversão de unidades e classificação
-- ============================================================================
--
-- Esta view realiza:
-- 1. Conversão de unidades (m/s ↔ knots, m ↔ feet)
-- 2. Classificação de fase de voo (ground, takeoff_landing, low, cruise, high_altitude)
-- 3. Classificação de tendência vertical (climbing, descending, level)
-- 4. Classificação de velocidade (slow, medium, fast, supersonic)
-- 5. Validação de dados (longitude, latitude, icao24)
--
-- A view filtra dados inválidos e enriquece cada evento com campos analíticos.
--

CREATE TEMPORARY VIEW enriched_flights AS
SELECT
    -- Identificadores e meta
    icao24,
    TRIM(callsign)                              AS callsign,
    origin_country,
    squawk,
    spi,
    position_source,
    
    -- Timestamps
    TO_TIMESTAMP(time_position, 'yyyy-MM-dd''T''HH:mm:ss') 
                                                AS time_position_ts,
    TO_TIMESTAMP(last_contact, 'yyyy-MM-dd''T''HH:mm:ss')
                                                AS last_contact_ts,
    event_time,

    -- Posição geográfica
    longitude,
    latitude,
    on_ground,

    -- Altitude (múltiplas unidades)
    altitude                                    AS altitude_m,
    altitude * 3.28084                          AS altitude_ft,
    geo_altitude * 3.28084                      AS geo_altitude_ft,

    -- Velocidade (múltiplas unidades)
    velocity                                    AS velocity_ms,
    velocity * 1.94384                          AS velocity_kts,

    -- Direção e taxa vertical
    heading,
    vertical_rate                               AS vrate_ms,
    vertical_rate * 196.85                      AS vrate_fpm,
    
    -- =========================================================================
    -- CLASSIFICAÇÕES ANALÍTICAS
    -- =========================================================================

    -- FASE DE VOO (altitude em pés)
    -- Baseado em altitude acima do solo para determinar fase operacional
    CASE
        WHEN on_ground = TRUE                    
            THEN 'ground'
        WHEN altitude * 3.28084 < 1000           
            THEN 'takeoff_landing'
        WHEN altitude * 3.28084 < 10000          
            THEN 'low'
        WHEN altitude * 3.28084 < 35000          
            THEN 'cruise'
        ELSE                                      
            'high_altitude'
    END                                         AS flight_phase,

    -- TENDÊNCIA VERTICAL
    -- Classifica movimento vertical para detectar padrões de subida/descida
    CASE
        WHEN vertical_rate >  2.0  
            THEN 'climbing'
        WHEN vertical_rate < -2.0  
            THEN 'descending'
        ELSE                            
            'level'
    END                                         AS vertical_trend,

    -- CATEGORIA DE VELOCIDADE (em knots)
    -- Faixas típicas de operação para aeronaves comerciais
    CASE
        WHEN velocity * 1.94384 < 100  
            THEN 'slow'
        WHEN velocity * 1.94384 < 300  
            THEN 'medium'
        WHEN velocity * 1.94384 < 500  
            THEN 'fast'
        ELSE                                
            'supersonic'
    END                                         AS speed_category

FROM state_vectors_source

-- ============================================================================
-- VALIDAÇÕES E FILTROS
-- ============================================================================
--
-- Icao24 obrigatório (identificador único)
WHERE icao24 IS NOT NULL
  -- Coordenadas devem estar dentro de limites válidos
  AND longitude BETWEEN -180 AND 180
  AND latitude  BETWEEN -90  AND 90;

-- =============================================================================
-- REFERÊNCIA DE CONVERSÃO
-- =============================================================================
--
-- Altitude:
--   1 metro = 3.28084 pés
--   1000 m = 3280.84 ft (aproximadamente)
--
-- Velocidade:
--   1 m/s = 1.94384 knots
--   10 m/s ≈ 19.4 knots
--
-- Taxa Vertical:
--   1 m/s = 196.85 feet per minute (fpm)
--   0.5 m/s ≈ 98 fpm (descida suave)
--   2.0 m/s ≈ 394 fpm (descida/subida moderada)
--
-- FASES DE VOO (típicas para comercial):
--   Ground: Na pista/estacionamento
--   Takeoff/Landing: < 1000 ft (manobras críticas)
--   Low: 1000-10000 ft (partida e aproximação)
--   Cruise: 10000-35000 ft (altitude de cruzeiro típica)
--   High Altitude: > 35000 ft (cruzeiro em altitude)
--
-- TENDÊNCIAS VERTICAIS (limiares):
--   > 2.0 m/s (≈ 394 fpm): subindo significativamente
--   < -2.0 m/s: descendo significativamente
--   entre -2.0 e 2.0: voo horizontal (variação de altitude mínima)
--
-- VELOCIDADES COMERCIAIS (em knots):
--   Slow: < 100 kts (situações anormais, taxi, falha de motor)
--   Medium: 100-300 kts (subida/descida, aproximação)
--   Fast: 300-500 kts (cruzeiro em altitude)
--   Supersonic: > 500 kts (militares, teste, erro de dados)
--
-- =============================================================================
