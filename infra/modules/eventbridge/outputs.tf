output "schedule_name" {
  description = "Nome do EventBridge Scheduler"
  value       = aws_scheduler_schedule.lambda_schedule.name
}

output "schedule_arn" {
  description = "ARN do EventBridge Scheduler"
  value       = aws_scheduler_schedule.lambda_schedule.arn
}

output "schedule_state" {
  description = "Estado do EventBridge Scheduler (ENABLED/DISABLED)"
  value       = aws_scheduler_schedule.lambda_schedule.state
}

output "scheduler_role_arn" {
  description = "ARN da IAM Role para Scheduler"
  value       = aws_iam_role.scheduler_role.arn
}

output "lambda_permission_statement_id" {
  description = "ID da statement de permissão Lambda para Scheduler"
  value       = aws_lambda_permission.allow_scheduler.statement_id
}

output "eventbridge_config_summary" {
  description = "Resumo das configurações do EventBridge Scheduler"
  value = {
    schedule_name         = aws_scheduler_schedule.lambda_schedule.name
    schedule_arn          = aws_scheduler_schedule.lambda_schedule.arn
    schedule_expression   = var.lambda_config.schedule
    schedule_state        = aws_scheduler_schedule.lambda_schedule.state
    target_lambda_arn     = var.lambda_arn
    target_lambda_name    = var.lambda_name
    scheduler_role_arn    = aws_iam_role.scheduler_role.arn
    lambda_permission_id  = aws_lambda_permission.allow_scheduler.statement_id
    description           = "EventBridge Scheduler dispara ${var.lambda_config.name} conforme agendamento: ${var.lambda_config.schedule}"
  }
}
