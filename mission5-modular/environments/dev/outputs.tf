# ─────────────────────────────────────────────
# Networking
# ─────────────────────────────────────────────

output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet ID 목록"
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet ID 목록"
  value       = module.networking.private_subnet_ids
}

output "sg_app_id" {
  description = "App security group ID"
  value       = module.networking.sg_app_id
}

output "sg_redis_id" {
  description = "Redis security group ID"
  value       = module.networking.sg_redis_id
}

output "app_instance_profile_name" {
  description = "IAM Instance Profile name"
  value       = module.networking.app_instance_profile_name
}

# ─────────────────────────────────────────────
# Secrets
# ─────────────────────────────────────────────

output "db_credentials_secret_arn" {
  description = "DB credentials secret ARN"
  value       = module.secrets.db_credentials_secret_arn
}

output "redis_auth_secret_arn" {
  description = "Redis auth secret ARN"
  value       = module.secrets.redis_auth_secret_arn
}

output "redis_auth_token" {
  description = "Redis AUTH token"
  value       = module.secrets.redis_auth_token
  sensitive   = true
}

# ─────────────────────────────────────────────
# Messaging
# ─────────────────────────────────────────────

output "sns_topic_arn" {
  description = "SNS topic ARN"
  value       = module.messaging.sns_topic_arn
}

output "sqs_queue_urls" {
  description = "메인 큐 URL 맵"
  value       = module.messaging.sqs_queue_urls
}

# ─────────────────────────────────────────────
# Cache
# ─────────────────────────────────────────────

output "redis_primary_endpoint" {
  description = "Redis primary endpoint"
  value       = module.cache.redis_primary_endpoint
}

output "redis_reader_endpoint" {
  description = "Redis reader endpoint"
  value       = module.cache.redis_reader_endpoint
}

output "redis_port" {
  description = "Redis port"
  value       = module.cache.redis_port
}
