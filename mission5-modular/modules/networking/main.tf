locals {
  name_prefix = "KJW-${var.project_name}-${var.environment}"
}

# ─────────────────────────────────────────────
# VPC
# ─────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

# ─────────────────────────────────────────────
# Subnets
# ─────────────────────────────────────────────

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.az_names[count.index]

  tags = {
    Name = "${local.name_prefix}-subnet-public-${substr(var.az_names[count.index], -2, 2)}"
  }
}

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.az_names[count.index]

  tags = {
    Name = "${local.name_prefix}-subnet-private-${substr(var.az_names[count.index], -2, 2)}"
  }
}

# ─────────────────────────────────────────────
# Internet Gateway
# ─────────────────────────────────────────────

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

# ─────────────────────────────────────────────
# Elastic IP + NAT Gateway
#
# single_nat_gateway = true  → EIP 1개, NAT 1개 (dev)
# single_nat_gateway = false → EIP AZ당 1개, NAT AZ당 1개 (prod)
# ─────────────────────────────────────────────

resource "aws_eip" "nat" {
  count  = var.single_nat_gateway ? 1 : length(var.az_names)
  domain = "vpc"

  tags = {
    Name = var.single_nat_gateway ? "${local.name_prefix}-eip-nat" : "${local.name_prefix}-eip-nat-${substr(var.az_names[count.index], -2, 2)}"
  }
}

resource "aws_nat_gateway" "main" {
  count = var.single_nat_gateway ? 1 : length(var.az_names)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = var.single_nat_gateway ? "${local.name_prefix}-nat" : "${local.name_prefix}-nat-${substr(var.az_names[count.index], -2, 2)}"
  }
}

# ─────────────────────────────────────────────
# Route Tables
# ─────────────────────────────────────────────

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.name_prefix}-rtb-public"
  }
}

# Private RT: single=true → 1개, false → AZ당 1개
resource "aws_route_table" "private" {
  count  = var.single_nat_gateway ? 1 : length(var.az_names)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[var.single_nat_gateway ? 0 : count.index].id
  }

  tags = {
    Name = var.single_nat_gateway ? "${local.name_prefix}-rtb-private" : "${local.name_prefix}-rtb-private-${substr(var.az_names[count.index], -2, 2)}"
  }
}

resource "aws_route_table_association" "public" {
  count = length(var.public_subnet_cidrs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count = length(var.private_subnet_cidrs)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[var.single_nat_gateway ? 0 : count.index].id
}

# ─────────────────────────────────────────────
# Security Groups
# ─────────────────────────────────────────────

resource "aws_security_group" "app" {
  name        = "${local.name_prefix}-sg-app"
  description = "App server: allow HTTP/HTTPS inbound, all outbound"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-sg-app"
  }
}

resource "aws_security_group" "redis" {
  name        = "${local.name_prefix}-sg-redis"
  description = "Redis: allow 6379 from app SG only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Redis from app"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-sg-redis"
  }
}

resource "aws_security_group" "vpce" {
  name        = "${local.name_prefix}-sg-vpce"
  description = "VPC Endpoint: allow 443 from app SG only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTPS from app"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-sg-vpce"
  }
}

# ─────────────────────────────────────────────
# IAM — Role / Policy / Instance Profile
# ─────────────────────────────────────────────

resource "aws_iam_role" "app" {
  name = "${local.name_prefix}-role-app"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-role-app"
  }
}

resource "aws_iam_role_policy" "app" {
  name = "${local.name_prefix}-policy-app"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          # SSM Session Manager
          "ssm:UpdateInstanceInformation",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply",
          # CloudWatch Logs
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "app" {
  name = "${local.name_prefix}-profile-app"
  role = aws_iam_role.app.name

  tags = {
    Name = "${local.name_prefix}-profile-app"
  }
}
