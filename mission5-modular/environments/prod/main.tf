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

  backend "s3" {
    bucket = "kjw-deepdive-bucket" # ← 본인 S3 버킷 이름으로 교체
    key    = "deepdive/mission5/prod/terraform.tfstate"
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

# ─────────────────────────────────────────────
# Module: networking
# single_nat_gateway = false (prod 고정 — AZ당 NAT 1개)
# ─────────────────────────────────────────────

module "networking" {
  source = "../../modules/networking"

  environment          = var.environment
  project_name         = var.project_name
  vpc_cidr             = var.vpc_cidr
  az_names             = var.az_names
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  single_nat_gateway   = false
}

# ─────────────────────────────────────────────
# Module: secrets
# ─────────────────────────────────────────────

module "secrets" {
  source = "../../modules/secrets"

  environment  = var.environment
  project_name = var.project_name
}

# ─────────────────────────────────────────────
# Module: messaging
# ─────────────────────────────────────────────

module "messaging" {
  source = "../../modules/messaging"

  environment  = var.environment
  project_name = var.project_name
  queues       = var.queues
}

# ─────────────────────────────────────────────
# Module: cache
# module output → module input 체이닝
# ─────────────────────────────────────────────

module "cache" {
  source = "../../modules/cache"

  environment  = var.environment
  project_name = var.project_name

  private_subnet_ids = module.networking.private_subnet_ids
  sg_redis_id        = module.networking.sg_redis_id
  redis_auth_token   = module.secrets.redis_auth_token

  node_type                = var.cache_node_type
  num_cache_clusters       = var.cache_num_clusters
  apply_immediately        = var.cache_apply_immediately
  snapshot_retention_limit = var.cache_snapshot_retention
}
