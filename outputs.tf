output "sns_topic_arn" {
  description = "SNS topic that receives the alerts."
  value       = aws_sns_topic.alerts.arn
}

output "trail_bucket" {
  description = "S3 bucket where CloudTrail stores log files."
  value       = aws_s3_bucket.trail_logs.id
}

output "central_rules" {
  description = "Central EventBridge rule name per detection."
  value       = { for key, rule in aws_cloudwatch_event_rule.central : key => rule.name }
}

output "forwarding_regions" {
  description = "Regions that forward matching events to the central Region."
  value       = local.forward_regions
}
