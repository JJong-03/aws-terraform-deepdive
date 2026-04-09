variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Project name used in resource naming"
  type        = string
  default     = "deepdive"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "az_names" {
  description = "사용 AZ 목록 (순서가 subnet CIDR 인덱스와 일치해야 함)"
  type        = list(string)
  default     = ["us-east-2a", "us-east-2c"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR 목록 ([0]=2a, [1]=2c)"
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR 목록 ([0]=2a, [1]=2c)"
  type        = list(string)
  default     = ["10.1.11.0/24", "10.1.12.0/24"]
}

# ─────────────────────────────────────────────
# Messaging
# ─────────────────────────────────────────────

variable "queues" {
  description = "큐별 설정 맵. message_retention_seconds로 dev/prod 차이를 줌"
  type = map(object({
    visibility_timeout_seconds = number
    max_receive_count          = number
    message_retention_seconds  = number
  }))
  default = {
    order = {
      visibility_timeout_seconds = 30
      max_receive_count          = 3
      message_retention_seconds  = 604800 # 7일
    }
    notification = {
      visibility_timeout_seconds = 60
      max_receive_count          = 5
      message_retention_seconds  = 604800 # 7일
    }
  }
}

# ─────────────────────────────────────────────
# Cache
# ─────────────────────────────────────────────

variable "cache_node_type" {
  description = "ElastiCache 노드 타입"
  type        = string
  default     = "cache.r6g.large"
}

variable "cache_num_clusters" {
  description = "캐시 노드 수 (primary + replica)"
  type        = number
  default     = 3
}

variable "cache_apply_immediately" {
  description = "변경사항 즉시 적용 여부"
  type        = bool
  default     = false
}

variable "cache_snapshot_retention" {
  description = "스냅샷 보관 기간 (일)"
  type        = number
  default     = 7
}
