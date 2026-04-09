output "redis_primary_endpoint" {
  description = "Redis primary endpoint address"
  value       = aws_elasticache_replication_group.main.primary_endpoint_address
}

output "redis_reader_endpoint" {
  description = "Redis reader endpoint address"
  value       = aws_elasticache_replication_group.main.reader_endpoint_address
}

output "redis_port" {
  description = "Redis port"
  value       = aws_elasticache_replication_group.main.port
}

output "redis_replication_group_id" {
  description = "ElastiCache Replication Group ID"
  value       = aws_elasticache_replication_group.main.id
}

output "redis_subnet_group_name" {
  description = "ElastiCache Subnet Group 이름"
  value       = aws_elasticache_subnet_group.main.name
}
