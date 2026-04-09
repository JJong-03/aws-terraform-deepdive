locals {
  name_prefix = "KJW-${var.project_name}-${var.environment}"
  # ElastiCache 식별자는 소문자만 허용
  id_prefix = lower("kjw-${var.project_name}-${var.environment}")
}

# ─────────────────────────────────────────────
# Parameter Group
# ─────────────────────────────────────────────

resource "aws_elasticache_parameter_group" "main" {
  family = "redis7"
  name   = "${local.id_prefix}-pg-redis"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  tags = {
    Name = "${local.name_prefix}-pg-redis"
  }
}

# ─────────────────────────────────────────────
# Subnet Group
# ─────────────────────────────────────────────

resource "aws_elasticache_subnet_group" "main" {
  name       = "${local.id_prefix}-subgrp-redis"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${local.name_prefix}-subgrp-redis"
  }
}

# ─────────────────────────────────────────────
# Replication Group
# ─────────────────────────────────────────────

resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "${local.id_prefix}-redis"
  description          = "${local.name_prefix} Redis Replication Group"

  engine         = "redis"
  engine_version = "7.0"
  node_type      = var.node_type

  num_cache_clusters         = var.num_cache_clusters
  automatic_failover_enabled = true
  multi_az_enabled           = true

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [var.sg_redis_id]

  transit_encryption_enabled = true
  at_rest_encryption_enabled = true
  auth_token                 = var.redis_auth_token

  parameter_group_name = aws_elasticache_parameter_group.main.name

  snapshot_retention_limit = var.snapshot_retention_limit
  snapshot_window          = "03:00-04:00"
  maintenance_window       = "sun:05:00-sun:06:00"

  apply_immediately = var.apply_immediately

  tags = {
    Name = "${local.name_prefix}-redis"
  }
}

# ─────────────────────────────────────────────
# SSM Parameter — Redis Endpoint 저장
# ─────────────────────────────────────────────

resource "aws_ssm_parameter" "redis_host" {
  name  = "/${var.project_name}/${var.environment}/redis/host"
  type  = "String"
  value = aws_elasticache_replication_group.main.primary_endpoint_address

  tags = {
    Name = "${local.name_prefix}-ssm-redis-host"
  }
}

resource "aws_ssm_parameter" "redis_reader_host" {
  name  = "/${var.project_name}/${var.environment}/redis/reader_host"
  type  = "String"
  value = aws_elasticache_replication_group.main.reader_endpoint_address

  tags = {
    Name = "${local.name_prefix}-ssm-redis-reader-host"
  }
}
