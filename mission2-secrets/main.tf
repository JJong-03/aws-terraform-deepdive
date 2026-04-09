terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # Mission 1과 동일한 S3 bucket, key만 분리
  backend "s3" {
    bucket = "kjw-deepdive-bucket" # ← Mission 1 backend에 입력한 bucket 이름과 동일하게 입력
    key    = "deepdive/mission2/terraform.tfstate"
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
  ssm_prefix  = "/${var.project_name}/${var.environment}"

  # dev=7일, prod=30일 — environment 하나로 자동 결정
  recovery_window = var.environment == "prod" ? 30 : 7

  # SSM Parameter Store에 등록할 설정값 맵
  ssm_parameters = {
    "app/port"      = "8080"
    "app/log_level" = "info"
    "db/port"       = "5432"
    "db/name"       = "deepdive"
    "redis/port"    = "6379"
  }
}

# ─────────────────────────────────────────────
# Random Passwords
# ─────────────────────────────────────────────

resource "random_password" "db" {
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]<>:?"
}

resource "random_password" "redis" {
  length  = 32
  special = false
}

# ─────────────────────────────────────────────
# SSM Parameter Store
# ─────────────────────────────────────────────

resource "aws_ssm_parameter" "app" {
  for_each = local.ssm_parameters

  name  = "${local.ssm_prefix}/${each.key}"
  type  = "String"
  value = each.value

  tags = {
    Name = "${local.name_prefix}-ssm-${replace(each.key, "/", "-")}"
  }
}

# ─────────────────────────────────────────────
# Secrets Manager — DB Credentials
# ─────────────────────────────────────────────

resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.project_name}/${var.environment}/db-credentials"
  description             = "DB credentials for ${local.name_prefix}"
  recovery_window_in_days = local.recovery_window

  tags = {
    Name = "${local.name_prefix}-secret-db"
  }
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string = jsonencode({
    username = "deepdive_admin"
    password = random_password.db.result
    dbname   = "deepdive"
  })
}

# ─────────────────────────────────────────────
# Secrets Manager — Redis Auth Token
# ─────────────────────────────────────────────

resource "aws_secretsmanager_secret" "redis" {
  name                    = "${var.project_name}/${var.environment}/redis-auth"
  description             = "Redis AUTH token for ${local.name_prefix}"
  recovery_window_in_days = local.recovery_window

  tags = {
    Name = "${local.name_prefix}-secret-redis"
  }
}

resource "aws_secretsmanager_secret_version" "redis" {
  secret_id     = aws_secretsmanager_secret.redis.id
  secret_string = random_password.redis.result
}
