output "region" {
  description = "The region the image is built in."
  value       = local.region
}

output "pipeline_arn" {
  description = "The ARN of the image pipeline. Start a build with `aws imagebuilder start-image-pipeline-execution --image-pipeline-arn <arn>`. Null in deployments mode, which creates no pipeline."
  value       = try(aws_imagebuilder_image_pipeline.this[0].arn, null)
}

output "pipeline_name" {
  description = "The name of the image pipeline. Null in deployments mode, which creates no pipeline."
  value       = try(aws_imagebuilder_image_pipeline.this[0].name, null)
}

output "recipe_arn" {
  description = "The ARN of the current image recipe. Null in deployments mode, where each deploy creates its own recipe instead."
  value       = try(aws_imagebuilder_image_recipe.this[0].arn, null)
}

output "recipe_name" {
  description = "The name of the current image recipe, which ends in a hash of its content. Null in deployments mode, where each deploy creates its own recipe instead."
  value       = try(aws_imagebuilder_image_recipe.this[0].name, null)
}

output "component_refs" {
  description = "Every component this module creates or references, in recipe order, with its real ARN regardless of source. Feeds an aws:ami deploy definition's infrastructure.components."
  value       = local.component_refs
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

output "pipeline_execution_policy_arn" {
  description = "The ARN of the policy that starts this pipeline and reads the images it produces. Null unless create_pipeline_execution_policy is true."
  value       = try(aws_iam_policy.pipeline_execution[0].arn, null)
}

output "notification_rule_arn" {
  description = "The EventBridge rule that forwards finished builds, or null when notifications are off."
  # Read off the rule itself rather than the flag that decides it: the flag is
  # derived from the header value, and a value derived from a secret makes the
  # whole output a secret.
  value = one(aws_cloudwatch_event_rule.notify[*].arn)
}
