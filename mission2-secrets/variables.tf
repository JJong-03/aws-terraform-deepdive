variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "environment" {
  description = "Deployment environment (dev | prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name used in resource naming and secret paths"
  type        = string
  default     = "deepdive"
}
