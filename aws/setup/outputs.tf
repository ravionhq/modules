output "role_arn" {
  description = "ARN of rvn-<ravion_id>, the role Ravion uses for account-wide work."
  value       = aws_iam_role.role.arn
}

output "deployments_role_arn" {
  description = "ARN of the deployments role, or empty when disabled."
  value       = try(aws_iam_role.deployments_role[0].arn, "")
}

output "terraform_role_arn" {
  description = "ARN of the Terraform role, or empty when disabled."
  value       = try(aws_iam_role.terraform_role[0].arn, "")
}

output "sandboxes_role_arn" {
  description = "ARN of the CI pipelines, GitHub runners and sandboxes role, or empty when disabled."
  value       = try(aws_iam_role.sandboxes_role[0].arn, "")
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider for https://oidc.ravion.com the roles trust."
  value       = local.ravion_oidc_provider_arn
}

output "role_version" {
  description = "Ravion role version this module installs (VERSION)."
  value       = local.ravion_role_version
}
