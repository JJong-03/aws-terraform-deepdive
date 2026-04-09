output "sns_topic_arn" {
  description = "SNS topic ARN"
  value       = aws_sns_topic.main.arn
}

output "sqs_queue_urls" {
  description = "메인 큐 URL 맵 ({ order = '...', notification = '...' })"
  value       = { for k, q in aws_sqs_queue.main : k => q.id }
}

output "sqs_queue_arns" {
  description = "메인 큐 ARN 맵 ({ order = '...', notification = '...' })"
  value       = { for k, q in aws_sqs_queue.main : k => q.arn }
}

output "dlq_queue_arns" {
  description = "DLQ ARN 맵 ({ order = '...', notification = '...' })"
  value       = { for k, q in aws_sqs_queue.dlq : k => q.arn }
}
