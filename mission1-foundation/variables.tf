variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "az_names" {
  description = "List of availability zones to use (only us-east-2a and us-east-2c allowed)"
  type        = list(string)
  default     = ["us-east-2a", "us-east-2c"]
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name used in resource naming"
  type        = string
  default     = "deepdive"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (index 0 = 2a, index 1 = 2c)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (index 0 = 2a, index 1 = 2c)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}
