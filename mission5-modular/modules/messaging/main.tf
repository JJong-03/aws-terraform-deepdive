locals {
  name_prefix = "KJW-${var.project_name}-${var.environment}"
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
  for_each = var.queues

  name                      = "${local.name_prefix}-sqs-${each.key}-dlq"
  message_retention_seconds = 1209600 # 14일 고정

  tags = {
    Name = "${local.name_prefix}-sqs-${each.key}-dlq"
  }
}

# ─────────────────────────────────────────────
# 메인 큐
# ─────────────────────────────────────────────

resource "aws_sqs_queue" "main" {
  for_each = var.queues

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
# ─────────────────────────────────────────────

resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  for_each = var.queues

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
  for_each = var.queues

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
  for_each = var.queues

  queue_url = aws_sqs_queue.main[each.key].id
  policy    = data.aws_iam_policy_document.sqs_policy[each.key].json
}

# ─────────────────────────────────────────────
# SNS → SQS Subscription
# ─────────────────────────────────────────────

resource "aws_sns_topic_subscription" "main" {
  for_each = var.queues

  topic_arn            = aws_sns_topic.main.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.main[each.key].arn
  raw_message_delivery = false

  depends_on = [aws_sqs_queue_policy.main]
}
