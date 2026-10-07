################################################################################
# Lambda Function
################################################################################

resource "aws_lambda_function" "this" {
  function_name = var.name
  description   = var.description
  role          = local.lambda_role_arn

  package_type = var.package_type
  publish      = var.version_publishing_enabled || length(local.aliases) > 0

  architectures                  = [var.architecture]
  memory_size                    = var.memory_size
  timeout                        = var.timeout
  kms_key_arn                    = var.kms_key_arn
  layers                         = var.layers
  reserved_concurrent_executions = var.reserved_concurrent_executions
  code_signing_config_arn        = var.code_signing_config_arn

  filename         = var.package_type == "Zip" ? var.filename : null
  source_code_hash = var.source_code_hash
  s3_bucket        = var.package_type == "Zip" ? local.effective_s3_bucket : null
  s3_key           = var.package_type == "Zip" ? local.effective_s3_key : null

  image_uri = var.package_type == "Image" ? local.effective_image_uri : null
  handler   = var.package_type == "Zip" ? var.handler : null
  runtime   = var.package_type == "Zip" ? var.runtime : null

  dynamic "environment" {
    for_each = length(var.environment_variables) > 0 ? [1] : []
    content {
      variables = var.environment_variables
    }
  }

  dynamic "vpc_config" {
    for_each = var.vpc_config != null ? [var.vpc_config] : []
    content {
      subnet_ids                  = vpc_config.value.subnet_ids
      security_group_ids          = vpc_config.value.security_group_ids
      ipv6_allowed_for_dual_stack = try(vpc_config.value.ipv6_allowed_for_dual_stack, null)
    }
  }

  dynamic "dead_letter_config" {
    for_each = var.dead_letter_target_arn != null ? [1] : []
    content {
      target_arn = var.dead_letter_target_arn
    }
  }

  dynamic "file_system_config" {
    for_each = var.file_system_configs
    content {
      arn              = file_system_config.value.arn
      local_mount_path = file_system_config.value.local_mount_path
    }
  }

  dynamic "image_config" {
    for_each = var.image_config != null ? [var.image_config] : []
    content {
      command           = try(image_config.value.command, null)
      entry_point       = try(image_config.value.entry_point, null)
      working_directory = try(image_config.value.working_directory, null)
    }
  }

  ephemeral_storage {
    size = var.ephemeral_storage_size
  }

  tracing_config {
    mode = var.tracing_mode
  }

  dynamic "snap_start" {
    for_each = var.snap_start_apply_on != null ? [1] : []
    content {
      apply_on = var.snap_start_apply_on
    }
  }

  tags = local.tags

  lifecycle {
    # Ravion deploy owns post-create code promotions; Terraform still manages
    # runtime and function configuration.
    ignore_changes = [
      image_uri,
      s3_bucket,
      s3_key,
    ]

    precondition {
      condition = (
        !var.lambda_at_edge_enabled ||
        (
          var.version_publishing_enabled &&
          var.package_type == "Zip" &&
          var.vpc_config == null &&
          length(var.environment_variables) == 0 &&
          length(var.layers) == 0 &&
          length(var.file_system_configs) == 0 &&
          var.dead_letter_target_arn == null &&
          var.architecture == "x86_64" &&
          var.timeout <= 30 &&
          var.memory_size <= 3008
        )
      )
      error_message = "Lambda@Edge constraints are violated. Review lambda_at_edge_enabled requirements in variables.tf and README."
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.managed,
    aws_iam_role_policy.inline,
    aws_cloudwatch_log_group.this,
    module.ecr,
    terraform_data.bootstrap_image
  ]
}
