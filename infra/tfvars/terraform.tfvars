control_account = "331504768406"

region                  = "us-east-1"
project_name            = "flight-radar-stream"
environment             = "production"

enable_vpc = true
nat_gateway_enabled = true
vpc_id = "vpc-022139f6bee3cbdd5"
subnet_ids = [
    "subnet-0051cb2e25a8a1cd7",
    "subnet-060fa607df99778da",
    "subnet-0033d0f717071e145"
]


############################################
# Lambda Functions Configuration
lambda_functions = {
  flights = {
    name              = "ingest-flights"
    handler           = "lambda_function.lambda_handler"
    runtime           = "python3.12"
    timeout           = 90
    memory_size       = 512
    ephemeral_storage = 512
    schedule          = "rate(5 minutes)"
    enabled           = true
    kinesis_stream    = "flight-radar-stream-flights"
    requires_opensky_credentials = true
    reserved_concurrent_executions = 0  # 0 = ON-DEMAND (sem custo fixo)
    tags = {
      Type   = "ingest"
      Source = "opensky-api"
    }
  }
  
  # Exemplo: próxima Lambda (descomente quando estiver pronto)
  # airports = {
  #   name              = "ingest-airports"
  #   handler           = "lambda_function.lambda_handler"
  #   runtime           = "python3.12"
  #   timeout           = 60
  #   memory_size       = 1024
  #   ephemeral_storage = 5120
  #   schedule          = "rate(1 hour)"
  #   enabled           = true
  #   kinesis_stream    = "flight-radar-stream-airports"
  #   requires_opensky_credentials = false
  #   reserved_concurrent_executions = 10
  #   tags = {
  #     Type   = "ingest"
  #     Source = "external-api"
  #   }
  # }
}


kinesis_streams = {
    flights   = { 
      stream_name = "flight-radar-kinesis-stream-flights"
      shard_count = 1 
    }  
}

datalake_role_name = "role-datalake-analytics"

buckets = {
  workspace = "lakehouse-workspace-33150"
  landing   = "lakehouse-landing-331504"
  raw       = "lakehouse-raw-331504"
}

# OpenSky API Credentials - CONFIGURE VIA VARIÁVEIS DE AMBIENTE!
# ⚠️  NÃO COMMIT CREDENCIAIS REAIS AQUI
# Use: export TF_VAR_OPENSKY_CLIENT_ID="seu_usuario" 
#      export TF_VAR_OPENSKY_CLIENT_SECRET="sua_senha"


# AWS Secrets Manager Configuration
secrets_recovery_window_days = 0  # Deleta imediatamente
secrets_log_retention_days   = 7

tags = {
  Environment = "production"
  Project     = "flight-radar-stream"
  ManagedBy   = "terraform"
}

