variable "environment" {
  description = "Deployment environment (dev | prod)"
  type        = string
}

variable "project_name" {
  description = "Project name used in resource naming"
  type        = string
}

# module.networking output에서 주입
variable "private_subnet_ids" {
  description = "Private subnet ID 목록 (module.networking.private_subnet_ids)"
  type        = list(string)
}

variable "sg_redis_id" {
  description = "Redis security group ID (module.networking.sg_redis_id)"
  type        = string
}

# module.secrets output에서 주입
variable "redis_auth_token" {
  description = "Redis AUTH token (module.secrets.redis_auth_token)"
  type        = string
  sensitive   = true
}

# 환경별로 다르게 주입할 캐시 설정
variable "node_type" {
  description = "ElastiCache 노드 타입 (dev: cache.t3.micro, prod: cache.r6g.large)"
  type        = string
  default     = "cache.t3.micro"
}

variable "num_cache_clusters" {
  description = "노드 수 (primary + replica). 최소 2 이상이어야 failover 가능"
  type        = number
  default     = 2
}

variable "apply_immediately" {
  description = "변경사항 즉시 적용 여부 (dev: true, prod: false)"
  type        = bool
  default     = true
}

variable "snapshot_retention_limit" {
  description = "스냅샷 보관 기간 (일)"
  type        = number
  default     = 1
}
