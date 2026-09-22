output "regions" {
  description = "AWS Regions with registry-wide Basic scan-on-push enabled."
  value       = sort(keys(aws_ecr_registry_scanning_configuration.this))
}

output "registry_ids" {
  description = "Map of Region to the AWS account's ECR registry ID."
  value       = { for region, configuration in aws_ecr_registry_scanning_configuration.this : region => configuration.registry_id }
}
