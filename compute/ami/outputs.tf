output "region" {
  description = "The region images are built in."
  value       = local.region
}

output "parent_image" {
  description = "The parent image builds start from: the image given, or the newest AMI the lookup found at apply time. A deploy looks a lookup up again when it starts."
  value       = local.parent_image

  precondition {
    condition     = local.parent_image != null
    error_message = "Set parent_image or parent_image_lookup."
  }
}

output "component_refs" {
  description = "Every component this module creates or references, in run order, as {name, arn, parameters}: its real ARN regardless of source, and the parameter values a deploy passes it unless the deploy overrides them."
  value       = local.component_refs
}

output "image_builder_infrastructure_configuration_arn" {
  description = "The ARN of the infrastructure configuration a build runs on."
  value       = aws_imagebuilder_infrastructure_configuration.this.arn
}

output "image_builder_distribution_configuration_arn" {
  description = "The ARN of the distribution configuration that names and tags each image in the build region."
  value       = aws_imagebuilder_distribution_configuration.this.arn
}

output "instance_role_arn" {
  description = "The ARN of the build instance's IAM role."
  value       = aws_iam_role.instance.arn
}

output "instance_role_name" {
  description = "The name of the build instance's IAM role, for attaching further policies."
  value       = aws_iam_role.instance.name
}
