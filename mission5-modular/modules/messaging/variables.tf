variable "environment" {
  description = "Deployment environment (dev | prod)"
  type        = string
}

variable "project_name" {
  description = "Project name used in resource naming"
  type        = string
}

variable "queues" {
  description = "큐별 설정 맵. 각 키가 큐 이름이 되고, 값으로 동작 파라미터를 지정한다."
  type = map(object({
    visibility_timeout_seconds = number
    max_receive_count          = number
    message_retention_seconds  = number
  }))
}
