# ─────────────────────────────────────────────
# Network
# ─────────────────────────────────────────────

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs ([0]=2a, [1]=2c)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs ([0]=2a, [1]=2c)"
  value       = aws_subnet.private[*].id
}

# ─────────────────────────────────────────────
# Security Groups
# ─────────────────────────────────────────────

output "sg_app_id" {
  description = "App security group ID"
  value       = aws_security_group.app.id
}

output "sg_redis_id" {
  description = "Redis security group ID"
  value       = aws_security_group.redis.id
}

output "sg_vpce_id" {
  description = "VPC endpoint security group ID"
  value       = aws_security_group.vpce.id
}

# ─────────────────────────────────────────────
# IAM
# ─────────────────────────────────────────────

output "app_role_arn" {
  description = "IAM Role ARN for the app instance profile"
  value       = aws_iam_role.app.arn
}

output "app_instance_profile_name" {
  description = "IAM Instance Profile name (use when attaching to EC2)"
  value       = aws_iam_instance_profile.app.name
}

output "iam_instance_profile_arn" {
  description = "IAM Instance Profile ARN (optional — use when ARN reference is needed)"
  value       = aws_iam_instance_profile.app.arn
}
