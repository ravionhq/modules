################################################################################
# Outputs
################################################################################

output "region" {
  description = "Region the release was published in."
  value       = var.region
}

output "parameter_name" {
  description = "Parameter the release is published at."
  value       = aws_ssm_parameter.release.name
}

output "parameter_arn" {
  description = "ARN of the published parameter."
  value       = aws_ssm_parameter.release.arn
}

output "release" {
  description = "The published release, as the pools read it."
  value       = local.release
}

output "ami_id" {
  description = "Image the release names, when it was verified."
  value       = var.verify_image ? one(data.aws_ami.host[*].id) : null
}
