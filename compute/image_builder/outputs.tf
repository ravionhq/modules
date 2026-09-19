output "region" {
  description = "The region the image is built in."
  value       = local.region
}

output "pipeline_arn" {
  description = "The ARN of the image pipeline. Start a build with `aws imagebuilder start-image-pipeline-execution --image-pipeline-arn <arn>`."
  value       = aws_imagebuilder_image_pipeline.this.arn
}

output "pipeline_name" {
  description = "The name of the image pipeline."
  value       = aws_imagebuilder_image_pipeline.this.name
}

output "recipe_arn" {
  description = "The ARN of the current image recipe."
  value       = aws_imagebuilder_image_recipe.this.arn
}

output "recipe_name" {
  description = "The name of the current image recipe, which ends in a hash of its content."
  value       = aws_imagebuilder_image_recipe.this.name
}

output "component_names" {
  description = "Names of the components this module created, keyed by component name. Each ends in a hash of its content."
  value       = { for name, component in aws_imagebuilder_component.this : name => component.name }
}

output "parent_image" {
  description = "The parent image the current recipe builds on."
  value       = local.parent_image
}

output "component_arns" {
  description = "ARNs of the components this module created, keyed by component name."
  value       = { for name, component in aws_imagebuilder_component.this : name => component.arn }
}

output "infrastructure_configuration_arn" {
  description = "The ARN of the infrastructure configuration."
  value       = aws_imagebuilder_infrastructure_configuration.this.arn
}

output "distribution_configuration_arn" {
  description = "The ARN of the distribution configuration."
  value       = aws_imagebuilder_distribution_configuration.this.arn
}

output "distribution_regions" {
  description = "Every region an image is produced in: the build region first, then the distribution regions."
  value       = local.all_regions
}

output "instance_role_arn" {
  description = "The ARN of the build instance's IAM role."
  value       = aws_iam_role.instance.arn
}

output "instance_role_name" {
  description = "The name of the build instance's IAM role, for attaching further policies."
  value       = aws_iam_role.instance.name
}

output "image_arn" {
  description = "The ARN of the image built during apply. Null unless build_on_apply is true."
  value       = try(aws_imagebuilder_image.this[0].arn, null)
}

output "ami_ids" {
  description = "AMI ids of the image built during apply, keyed by region. Empty unless build_on_apply is true."
  value = {
    for ami in try(tolist(aws_imagebuilder_image.this[0].output_resources[0].amis), []) : ami.region => ami.image
  }
}
