################################################################################
# Outputs
################################################################################

output "regions" {
  description = "AWS Regions where GuardDuty is enabled."
  value       = sort(var.regions)
}

output "detector_ids" {
  description = "Map of Region to GuardDuty detector ID."
  value       = { for region, detector in aws_guardduty_detector.this : region => detector.id }
}

output "detector_arns" {
  description = "Map of Region to GuardDuty detector ARN."
  value       = { for region, detector in aws_guardduty_detector.this : region => detector.arn }
}

output "account_id" {
  description = "AWS account ID that owns the GuardDuty detectors."
  value       = data.aws_caller_identity.current.account_id
}

output "protection_plans" {
  description = "Map of GuardDuty protection plan (feature name) to whether it is enabled in every Region."
  value       = local.protection_plans
}
