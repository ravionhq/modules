################################################################################
# Image Pipeline
################################################################################

resource "aws_imagebuilder_image_pipeline" "this" {
  region                           = local.region
  name                             = var.name
  description                      = var.description
  status                           = var.pipeline_enabled ? "ENABLED" : "DISABLED"
  image_recipe_arn                 = aws_imagebuilder_image_recipe.this.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.this.arn
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.this.arn
  enhanced_image_metadata_enabled  = var.enhanced_image_metadata_enabled

  image_tests_configuration {
    image_tests_enabled = var.image_tests_enabled
    timeout_minutes     = var.image_tests_timeout_minutes
  }

  dynamic "schedule" {
    for_each = var.schedule_expression == null ? [] : [var.schedule_expression]

    content {
      schedule_expression                = schedule.value
      pipeline_execution_start_condition = var.schedule_start_condition
    }
  }

  tags = local.tags
}

################################################################################
# Image
#
# Optional build during apply. A changed recipe replaces this resource, which
# is a new build; deleting the old image record leaves its AMIs in place.
################################################################################

resource "aws_imagebuilder_image" "this" {
  count = var.build_on_apply ? 1 : 0

  region                           = local.region
  image_recipe_arn                 = aws_imagebuilder_image_recipe.this.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.this.arn
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.this.arn
  enhanced_image_metadata_enabled  = var.enhanced_image_metadata_enabled

  image_tests_configuration {
    image_tests_enabled = var.image_tests_enabled
    timeout_minutes     = var.image_tests_timeout_minutes
  }

  tags = local.tags

  timeouts {
    create = "${local.build_timeout_minutes}m"
  }
}
