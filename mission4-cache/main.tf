terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Mission 1~3과 동일한 S3 bucket, key만 분리
  backend "s3" {
    bucket = "kjw-deepdive-bucket" # ← Mission 1 backend에 입력한 bucket 이름과 동일하게 입력
    key    = "deepdive/mission4/terraform.tfstate"
    region = "us-east-2"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Owner       = "student02"
      Environment = var.environment
      Project     = var.project_name
    }
  }
}

locals {
  name_prefix = "KJW-${var.project_name}-${var.environment}"

  # ElastiCache 식별자는 소문자만 허용 — 대문자 포함 시 apply 실패
  id_prefix = lower("kjw-${var.project_name}-${var.environment}")

  # dev: 즉시 적용, prod: 유지보수 창 대기
  apply_immediately = var.environment == "prod" ? false : true
}

# ─────────────────────────────────────────────
# Remote State — Mission 1 (네트워크/보안)
# ─────────────────────────────────────────────

data "terraform_remote_state" "mission1" {
  backend = "s3"
  config = {
    bucket = "kjw-deepdive-bucket" # ← backend bucket과 동일하게 입력
    key    = "deepdive/mission1/terraform.tfstate"
    region = "us-east-2"
  }
}

# ─────────────────────────────────────────────
# Remote State — Mission 2 (Redis auth token)
# ─────────────────────────────────────────────

data "terraform_remote_state" "mission2" {
  backend = "s3"
  config = {
    bucket = "kjw-deepdive-bucket" # ← backend bucket과 동일하게 입력
    key    = "deepdive/mission2/terraform.tfstate"
    region = "us-east-2"
  }
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
# Subnet Group (Mission 1 private subnets 사용)
# ─────────────────────────────────────────────

resource "aws_elasticache_subnet_group" "main" {
  name       = "${local.id_prefix}-subgrp-redis"
  subnet_ids = data.terraform_remote_state.mission1.outputs.private_subnet_ids

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
  node_type      = "cache.t3.micro"

  num_cache_clusters         = 2
  automatic_failover_enabled = true
  multi_az_enabled           = true

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [data.terraform_remote_state.mission1.outputs.sg_redis_id]

  # 보안 설정 — auth_token은 transit_encryption_enabled = true 필수
  transit_encryption_enabled = true
  at_rest_encryption_enabled = true
  auth_token                 = data.terraform_remote_state.mission2.outputs.redis_auth_token

  parameter_group_name = aws_elasticache_parameter_group.main.name

  snapshot_retention_limit = 1
  snapshot_window          = "03:00-04:00"
  maintenance_window       = "sun:05:00-sun:06:00"

  apply_immediately = local.apply_immediately

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
