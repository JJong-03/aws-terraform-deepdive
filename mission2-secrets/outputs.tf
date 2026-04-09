# ─────────────────────────────────────────────
# SSM
# ─────────────────────────────────────────────

output "ssm_parameter_prefix" {
  description = "SSM Parameter Store 경로 prefix (후속 미션 참조용)"
  value       = local.ssm_prefix
}

# ─────────────────────────────────────────────
# Secrets Manager — DB
# ─────────────────────────────────────────────

output "db_credentials_secret_arn" {
  description = "DB credentials secret ARN"
  value       = aws_secretsmanager_secret.db.arn
}

output "db_credentials_secret_name" {
  description = "DB credentials secret 이름 (콘솔 확인 / 참조용)"
  value       = aws_secretsmanager_secret.db.name
}

# ─────────────────────────────────────────────
# Secrets Manager — Redis
# ─────────────────────────────────────────────

output "redis_auth_secret_arn" {
  description = "Redis auth secret ARN"
  value       = aws_secretsmanager_secret.redis.arn
}

output "redis_auth_token" {
  description = "Redis AUTH token (Mission 4 auth_token 파라미터로 직접 사용)"
  value       = random_password.redis.result
  sensitive   = true
}
