###############################################
# AWS Secrets Manager Outputs
###############################################

output "secrets_manager_info" {
  description = "Information about AWS Secrets Manager secrets"
  value = {
    opensky_credentials = {
      secret_id         = module.secrets_manager.secret_id
      secret_arn        = module.secrets_manager.secret_arn
      version_id        = module.secrets_manager.secret_version_id
      access_policy_arn = module.secrets_manager.secret_access_policy
      log_group         = module.secrets_manager.cloudwatch_log_group
    }
  }
}

###############################################
# Kinesis Data Streams Outputs
###############################################

output "kinesis_stream_arns" {
  description = "ARNs dos streams Kinesis criados"
  value       = module.kinesis_data_stream.kinesis_stream_arns
}

output "kinesis_stream_names" {
  description = "Nomes dos streams Kinesis criados"
  value       = module.kinesis_data_stream.kinesis_stream_names
}

output "kinesis_streams_info" {
  description = "Informações completas dos streams Kinesis"
  value       = module.kinesis_data_stream.kinesis_streams_info
}

output "kinesis_stream_endpoints" {
  description = "Endpoints dos streams para conexão"
  value       = module.kinesis_data_stream.kinesis_stream_endpoints
}

###############################################
# Lambda Ingest Functions Outputs
###############################################

output "lambda_functions" {
  description = "Informações sobre as funções Lambda criadas"
  value = {
    for key, lambda_module in module.lambda_ingest :
    key => {
      name              = lambda_module.lambda_name
      arn               = lambda_module.lambda_arn
      role_arn          = lambda_module.lambda_role_arn
      log_group         = lambda_module.lambda_log_group
      config            = lambda_module.lambda_config_summary
    }
  }
}

output "lambda_functions_summary" {
  description = "Resumo de todas as funções Lambda"
  value = {
    for key, lambda_module in module.lambda_ingest :
    key => {
      function_name = lambda_module.lambda_config_summary.function_name
      function_arn  = lambda_module.lambda_config_summary.function_arn
      runtime       = lambda_module.lambda_config_summary.runtime
      timeout       = lambda_module.lambda_config_summary.timeout
      memory        = lambda_module.lambda_config_summary.memory_size
      concurrency   = lambda_module.lambda_config_summary.concurrency_mode
    }
  }
}

###############################################
# EventBridge Schedulers Outputs
###############################################

output "eventbridge_schedulers" {
  description = "Informações sobre os agendadores EventBridge Scheduler"
  value = {
    for key, scheduler_module in module.eventbridge :
    key => {
      schedule_name      = scheduler_module.schedule_name
      schedule_arn       = scheduler_module.schedule_arn
      schedule_state     = scheduler_module.schedule_state
      scheduler_role_arn = scheduler_module.scheduler_role_arn
    }
  }
}

output "eventbridge_schedulers_summary" {
  description = "Resumo dos agendadores EventBridge Scheduler com detalhes de execução"
  value = {
    for key, scheduler_module in module.eventbridge :
    key => {
      schedule_name      = scheduler_module.schedule_name
      schedule_arn       = scheduler_module.schedule_arn
      state              = scheduler_module.schedule_state
      role_arn           = scheduler_module.scheduler_role_arn
    }
  }
}

###############################################
# Integration Summary
###############################################

output "pipeline_summary" {
  description = "Resumo completo do pipeline de ingestão"
  value = {
    lambda_functions = {
      for key, lambda_module in module.lambda_ingest :
      key => {
        name            = lambda_module.lambda_config_summary.function_name
        schedule        = module.eventbridge[key].eventbridge_config_summary.schedule_expression
        target_stream   = var.lambda_functions[key].kinesis_stream
        timeout         = lambda_module.lambda_config_summary.timeout
        memory          = lambda_module.lambda_config_summary.memory_size
        concurrency     = lambda_module.lambda_config_summary.concurrency_mode
      }
    }
    kinesis_streams = {
      for key, stream_info in module.kinesis_data_stream.kinesis_streams_info :
      key => {
        name       = stream_info.name
        mode       = stream_info.mode
        retention  = "${stream_info.retention_hours}h"
      }
    }
  }
}