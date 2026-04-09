terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Mission 1/2와 동일한 S3 bucket, key만 분리
  backend "s3" {
    bucket = "kjw-deepdive-bucket" # ← Mission 1 backend에 입력한 bucket 이름과 동일하게 입력
    key    = "deepdive/mission3/terraform.tfstate"
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

  # 큐별 설정 맵 — for_each의 기준이 되는 단일 소스
  queues = {
    order = {
      visibility_timeout_seconds = 30
      max_receive_count          = 3
      message_retention_seconds  = 345600 # 4일
    }
    notification = {
      visibility_timeout_seconds = 60
      max_receive_count          = 5
      message_retention_seconds  = 345600 # 4일
    }
  }
}

# ─────────────────────────────────────────────
# SNS Topic
# ─────────────────────────────────────────────

resource "aws_sns_topic" "main" {
  name = "${local.name_prefix}-sns-events"

  tags = {
    Name = "${local.name_prefix}-sns-events"
  }
}

# ─────────────────────────────────────────────
# DLQ (메인 큐보다 먼저 생성 — redrive_policy 참조 순서)
# ─────────────────────────────────────────────

resource "aws_sqs_queue" "dlq" {
  for_each = local.queues

  name                      = "${local.name_prefix}-sqs-${each.key}-dlq"
  message_retention_seconds = 1209600 # 14일

  tags = {
    Name = "${local.name_prefix}-sqs-${each.key}-dlq"
  }
}

# ─────────────────────────────────────────────
# 메인 큐 (redrive_policy에서 DLQ ARN 참조)
# ─────────────────────────────────────────────

resource "aws_sqs_queue" "main" {
  for_each = local.queues

  name                       = "${local.name_prefix}-sqs-${each.key}"
  visibility_timeout_seconds = each.value.visibility_timeout_seconds
  message_retention_seconds  = each.value.message_retention_seconds

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[each.key].arn
    maxReceiveCount     = each.value.max_receive_count
  })

  tags = {
    Name = "${local.name_prefix}-sqs-${each.key}"
  }
}

# ─────────────────────────────────────────────
# DLQ Redrive Allow Policy
# 각 DLQ는 자신의 메인 큐에서만 redrive 허용
# ─────────────────────────────────────────────

resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  for_each = local.queues

  queue_url = aws_sqs_queue.dlq[each.key].id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.main[each.key].arn]
  })
}

# ─────────────────────────────────────────────
# Queue Policy — SNS → SQS 전송 허용
# ─────────────────────────────────────────────

data "aws_iam_policy_document" "sqs_policy" {
  for_each = local.queues

  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.main[each.key].arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.main.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "main" {
  for_each = local.queues

  queue_url = aws_sqs_queue.main[each.key].id
  policy    = data.aws_iam_policy_document.sqs_policy[each.key].json
}

# ─────────────────────────────────────────────
# SNS → SQS Subscription
# queue policy 생성 완료 후 subscription 생성 (레이스 방지)
# ─────────────────────────────────────────────

resource "aws_sns_topic_subscription" "main" {
  for_each = local.queues

  topic_arn            = aws_sns_topic.main.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.main[each.key].arn
  raw_message_delivery = false

  depends_on = [aws_sqs_queue_policy.main]
}
