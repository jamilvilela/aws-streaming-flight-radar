-- ============================================================================
-- Redshift DDL: Flight Data Schema
-- ============================================================================
-- Tables for storing enriched flight data from KDA Flink pipeline
-- 
-- Architecture:
-- • state_vectors (fact table): Raw enriched ADS-B messages
-- • state_vectors_1min_summary (aggregation): Country-level 1-min summaries
-- • state_vectors_altitude_bands (aggregation): Altitude band distribution
-- • state_vectors_phase_changes (events): Flight phase transitions
--
-- Update Strategy: INSERT OVERWRITE (Flink 1.19 sends incremental batches)
-- ============================================================================

-- ============================================================================
-- SCHEMA: flight_radar
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS flight_radar;

-- ============================================================================
-- TABLE 1: state_vectors (FACT TABLE)
-- ============================================================================
-- Enriched ADS-B data from Flink with unit conversions and classifications
--
-- Data Source: KDA Flink sink "enriched-raw" (Kinesis stream)
-- Cardinality: ~50,000-100,000 records/minute
-- Primary Purpose: Historical archive, detailed analysis
-- Retention: 90 days (configurable via Redshift retention policies)

CREATE TABLE IF NOT EXISTS flight_radar.state_vectors (
    -- Event metadata
    event_timestamp BIGINT NOT NULL,
    event_timestamp_utc TIMESTAMP NOT NULL SORTKEY DISTKEY,
    
    -- Aircraft identifiers
    icao24 VARCHAR(8) NOT NULL,
    callsign VARCHAR(8),
    origin_country VARCHAR(64),
    
    -- Position data
    longitude DOUBLE PRECISION,
    latitude DOUBLE PRECISION,
    
    -- Altitude (converted to feet in Flink)
    altitude_ft DOUBLE PRECISION,
    
    -- Velocity (converted to knots in Flink)
    velocity_kts DOUBLE PRECISION,
    true_track DOUBLE PRECISION,
    
    -- Vertical rate (converted to feet/min in Flink)
    vertical_rate_fpm DOUBLE PRECISION,
    
    -- Enrichment: Flight phase classification
    -- Values: CRUISE, CLIMB, DESCENT, LEVEL, GROUND, UNKNOWN
    flight_phase VARCHAR(16) NOT NULL,
    
    -- Enrichment: Vertical trend classification
    -- Values: CLIMBING, DESCENDING, LEVEL, GROUND
    vertical_trend VARCHAR(16) NOT NULL,
    
    -- Enrichment: Speed category
    -- Values: GROUND, SLOW, NORMAL, FAST, SUPERSONIC
    speed_category VARCHAR(16),
    
    -- Data quality flags
    position_source SMALLINT,
    is_on_ground BOOLEAN,
    time_position BIGINT,
    last_contact BIGINT
)
DISTKEY (event_timestamp_utc)
SORTKEY (event_timestamp_utc, icao24);

-- ============================================================================
-- TABLE 2: state_vectors_1min_summary (AGGREGATION)
-- ============================================================================
-- 1-minute rollups by country and flight phase
--
-- Data Source: KDA Flink sink "positions-1min" (Kinesis stream)
-- Cardinality: ~100-300 records/minute
-- Primary Purpose: Real-time dashboard, monitoring
-- Refresh: Every minute

CREATE TABLE IF NOT EXISTS flight_radar.state_vectors_1min_summary (
    window_start TIMESTAMP NOT NULL,
    window_end TIMESTAMP NOT NULL,
    origin_country VARCHAR(64) NOT NULL,
    flight_phase VARCHAR(16) NOT NULL,
    
    aircraft_count BIGINT,
    avg_altitude_ft DOUBLE PRECISION,
    avg_velocity_kts DOUBLE PRECISION,
    avg_latitude DOUBLE PRECISION,
    avg_longitude DOUBLE PRECISION,
    
    -- Aggregate metrics
    climbing_count BIGINT,
    descending_count BIGINT,
    level_count BIGINT,
    ground_count BIGINT,
    
    ingestion_timestamp TIMESTAMP DEFAULT GETDATE()
)
DISTKEY (origin_country)
SORTKEY (window_start, origin_country);

-- ============================================================================
-- TABLE 3: state_vectors_altitude_bands (AGGREGATION)
-- ============================================================================
-- 1-minute altitude band distribution (useful for traffic density)
--
-- Data Source: KDA Flink sink "altitude-bands" (Kinesis stream)
-- Cardinality: ~500-1,000 records/minute
-- Primary Purpose: Airspace analysis, congestion detection
-- Refresh: Every minute

CREATE TABLE IF NOT EXISTS flight_radar.state_vectors_altitude_bands (
    window_start TIMESTAMP NOT NULL,
    window_end TIMESTAMP NOT NULL,
    flight_phase VARCHAR(16) NOT NULL,
    vertical_trend VARCHAR(16) NOT NULL,
    
    -- Altitude bands (FL000 = 0ft, FL100 = 10,000ft, etc)
    altitude_band VARCHAR(16) NOT NULL,
    
    aircraft_count BIGINT,
    avg_velocity_kts DOUBLE PRECISION,
    max_altitude_ft DOUBLE PRECISION,
    min_altitude_ft DOUBLE PRECISION,
    
    ingestion_timestamp TIMESTAMP DEFAULT GETDATE()
)
DISTKEY (altitude_band)
SORTKEY (window_start, altitude_band);

-- ============================================================================
-- TABLE 4: state_vectors_phase_changes (EVENTS)
-- ============================================================================
-- Significant vertical movements (phase changes)
--
-- Data Source: KDA Flink sink "phase-changes" (Kinesis stream)
-- Cardinality: ~100-500 records/minute
-- Primary Purpose: Event streaming, alerting, anomaly detection
-- Filter Criteria: vertical_trend changed AND |vrate_fpm| > 500 (significant climb/descent)

CREATE TABLE IF NOT EXISTS flight_radar.state_vectors_phase_changes (
    window_start TIMESTAMP NOT NULL,
    window_end TIMESTAMP NOT NULL,
    
    icao24 VARCHAR(8) NOT NULL,
    callsign VARCHAR(8),
    origin_country VARCHAR(64),
    
    -- Position at event
    longitude DOUBLE PRECISION,
    latitude DOUBLE PRECISION,
    altitude_ft DOUBLE PRECISION,
    
    -- Phase change details
    previous_flight_phase VARCHAR(16),
    current_flight_phase VARCHAR(16) NOT NULL,
    vertical_rate_fpm DOUBLE PRECISION NOT NULL,
    
    -- Severity classification (based on vertical_rate)
    climb_rate_category VARCHAR(16),  -- NORMAL, AGGRESSIVE, EXTREME
    
    ingestion_timestamp TIMESTAMP DEFAULT GETDATE()
)
DISTKEY (icao24)
SORTKEY (window_start, icao24);

-- ============================================================================
-- MATERIALIZED VIEWS: For QuickSight Integration
-- ============================================================================

-- MV 1: Active Aircraft Summary
CREATE MATERIALIZED VIEW flight_radar.mv_active_aircraft_summary AS
SELECT
    GETDATE() as report_timestamp,
    COUNT(DISTINCT icao24) as total_active_aircraft,
    COUNT(CASE WHEN flight_phase = 'CRUISE' THEN 1 END) as cruising_count,
    COUNT(CASE WHEN flight_phase = 'CLIMB' THEN 1 END) as climbing_count,
    COUNT(CASE WHEN flight_phase = 'DESCENT' THEN 1 END) as descending_count,
    COUNT(CASE WHEN flight_phase = 'GROUND' THEN 1 END) as ground_count,
    COUNT(DISTINCT origin_country) as countries_represented,
    ROUND(AVG(altitude_ft)) as avg_altitude_ft,
    ROUND(AVG(velocity_kts)) as avg_velocity_kts,
    MAX(altitude_ft) as max_altitude_ft,
    MIN(CASE WHEN altitude_ft > 0 THEN altitude_ft END) as min_altitude_ft
FROM flight_radar.state_vectors
WHERE event_timestamp_utc > DATEADD(MINUTE, -5, GETDATE());

-- MV 2: Top Countries by Aircraft Count
CREATE MATERIALIZED VIEW flight_radar.mv_top_countries AS
SELECT TOP 50
    origin_country,
    COUNT(DISTINCT icao24) as aircraft_count,
    COUNT(*) as total_records,
    ROUND(AVG(altitude_ft)) as avg_altitude_ft,
    ROUND(AVG(velocity_kts)) as avg_velocity_kts,
    GETDATE() as last_update
FROM flight_radar.state_vectors
WHERE event_timestamp_utc > DATEADD(HOUR, -1, GETDATE())
GROUP BY origin_country
ORDER BY aircraft_count DESC;

-- MV 3: Phase Transitions Events
CREATE MATERIALIZED VIEW flight_radar.mv_recent_phase_changes AS
SELECT
    icao24,
    callsign,
    origin_country,
    previous_flight_phase,
    current_flight_phase,
    vertical_rate_fpm,
    climb_rate_category,
    window_start,
    DATEDIFF(SECOND, window_start, GETDATE()) as seconds_ago
FROM flight_radar.state_vectors_phase_changes
WHERE window_start > DATEADD(MINUTE, -30, GETDATE())
ORDER BY window_start DESC;

-- ============================================================================
-- INDEXES: For Query Performance
-- ============================================================================

-- Performance: Recent queries (last N hours)
CREATE INDEX idx_state_vectors_timestamp 
ON flight_radar.state_vectors (event_timestamp_utc DESC);

-- Performance: Aircraft lookup
CREATE INDEX idx_state_vectors_icao24 
ON flight_radar.state_vectors (icao24, event_timestamp_utc DESC);

-- Performance: Geographic queries
CREATE INDEX idx_state_vectors_location 
ON flight_radar.state_vectors (latitude, longitude);

-- ============================================================================
-- GRANTS: User Permissions
-- ============================================================================
-- Note: Execute these as admin after creating users

-- GRANT USAGE ON SCHEMA flight_radar TO readonly_user;
-- GRANT SELECT ON ALL TABLES IN SCHEMA flight_radar TO readonly_user;
-- GRANT SELECT ON ALL MATERIALIZED VIEWS IN SCHEMA flight_radar TO readonly_user;

-- GRANT USAGE ON SCHEMA flight_radar TO ingest_user;
-- GRANT INSERT, UPDATE, DELETE ON flight_radar.state_vectors TO ingest_user;
-- GRANT INSERT, UPDATE, DELETE ON flight_radar.state_vectors_1min_summary TO ingest_user;

-- ============================================================================
-- COMMENTS: Documentation
-- ============================================================================

COMMENT ON SCHEMA flight_radar IS 'Flight radar real-time data warehouse';

COMMENT ON TABLE flight_radar.state_vectors IS 
'Enriched ADS-B state vectors with flight phase classification. Source: KDA Flink sink "enriched-raw". ~100k records/min';

COMMENT ON TABLE flight_radar.state_vectors_1min_summary IS 
'1-minute aggregations by country and flight phase. Source: KDA Flink sink "positions-1min". For dashboards.';

COMMENT ON TABLE flight_radar.state_vectors_altitude_bands IS 
'Altitude band distribution for traffic analysis. Source: KDA Flink sink "altitude-bands". ~1k records/min';

COMMENT ON TABLE flight_radar.state_vectors_phase_changes IS 
'Significant vertical movements/phase transitions. Source: KDA Flink sink "phase-changes". For anomaly detection.';
