control_account = "331504768406"

region                  = "us-east-1"
project_name            = "flight-radar-stream"

kinesis_streams = {
    flights   = { shard_count = 10 }  # Shards dedicados para flights
    airports  = { shard_count = 1 }
    airplanes = { shard_count = 1 }
}

ingestion_schedule      = "rate(60 seconds)"
lambda_ingest_timeout   = 30
lambda_processor_timeout = 60

datalake_role_name = "role-datalake-analytics"

buckets = {
  workspace = "lakehouse-workspace-331504768406"
  landing   = "lakehouse-landing-331504768406"
  raw       = "lakehouse-raw-331504768406"
}

databases = {
  raw      = "raw_db"
}

tables = {
  etl_control  = "etl_control"
  data_quality = "data_quality_metrics"
}

users = {
  datalake_admin = {
    name = "datalake-admin"
  }
  datalake_user1 = {
    name = "datalake-user-01"
  }
}
