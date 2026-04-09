output "ssm_parameter_prefix" {
  description = "SSM Parameter Store 경로 prefix"
  value       = local.ssm_prefix
}

output "db_credentials_secret_arn" {
  description = "DB credentials secret ARN"
  value       = aws_secretsmanager_secret.db.arn
}

output "db_credentials_secret_name" {
  description = "DB credentials secret 이름"
  value       = aws_secretsmanager_secret.db.name
}

output "redis_auth_secret_arn" {
  description = "Redis auth secret ARN"
  value       = aws_secretsmanager_secret.redis.arn
}

output "redis_auth_token" {
  description = "Redis AUTH token (module.cache로 체이닝)"
  value       = random_password.redis.result
  sensitive   = true
}
