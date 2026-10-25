################################################################################
# Outputs
################################################################################

output "regions" {
  description = "AWS Regions covered by GuardDuty, registry-wide Basic ECR scan-on-push and optional CloudTrail."
  value       = sort(var.regions)
}

output "cloudtrail_arns" {
  description = "Map of Region to CloudTrail trail ARN, empty when disabled."
  value       = { for region, trail in aws_cloudtrail.this : region => trail.arn }
}

output "cloudtrail_bucket_name" {
  description = "CloudTrail audit log bucket name, or null when disabled."
  value       = var.cloudtrail_enabled ? aws_s3_bucket.cloudtrail[0].id : null
}

output "cloudtrail_bucket_arn" {
  description = "CloudTrail audit log bucket ARN, or null when disabled."
  value       = var.cloudtrail_enabled ? aws_s3_bucket.cloudtrail[0].arn : null
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
  description = "AWS account ID where the compliance baseline is managed."
  value       = data.aws_caller_identity.current.account_id
}

output "protection_plans" {
  description = "Map of GuardDuty protection plan (feature name) to whether it is enabled in every Region."
  value       = local.protection_plans
}

output "registry_ids" {
  description = "Map of Region to the ECR registry ID managed by the compliance baseline."
  value       = { for region, configuration in aws_ecr_registry_scanning_configuration.this : region => configuration.registry_id }
}
