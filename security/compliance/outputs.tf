################################################################################
# Outputs
################################################################################

output "regions" {
  description = "AWS Regions where GuardDuty and registry-wide Basic ECR scan-on-push are enabled."
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
