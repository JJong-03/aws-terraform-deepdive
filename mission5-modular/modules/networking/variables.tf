variable "environment" {
  description = "Deployment environment (dev | prod)"
  type        = string
}

variable "project_name" {
  description = "Project name used in resource naming"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "az_names" {
  description = "List of availability zones (e.g. [us-east-2a, us-east-2c]). Order must match subnet CIDRs."
  type        = list(string)

  validation {
    condition     = length(var.az_names) >= 2
    error_message = "az_names must contain at least 2 availability zones."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets. Index must match az_names order."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "public_subnet_cidrs must contain at least 2 entries."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets. Index must match az_names order."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "private_subnet_cidrs must contain at least 2 entries."
  }
}

variable "single_nat_gateway" {
  description = "true = NAT 1개(dev 절약), false = AZ당 NAT 1개(prod 고가용성)"
  type        = bool
  default     = true
}
