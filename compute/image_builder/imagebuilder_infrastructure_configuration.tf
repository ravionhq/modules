################################################################################
# Infrastructure Configuration
################################################################################

resource "aws_imagebuilder_infrastructure_configuration" "this" {
  region                        = local.region
  name                          = var.name
  description                   = var.description
  instance_profile_name         = aws_iam_instance_profile.instance.name
  instance_types                = var.instance_types
  subnet_id                     = var.subnet_id
  security_group_ids            = var.subnet_id == null ? null : var.security_group_ids
  terminate_instance_on_failure = var.terminate_instance_on_failure

  instance_metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  dynamic "logging" {
    for_each = var.log_bucket == null ? [] : [var.log_bucket]

    content {
      s3_logs {
        s3_bucket_name = logging.value
        s3_key_prefix  = local.log_prefix
      }
    }
  }

  # Tags written on the build and test instances.
  resource_tags = local.tags
  tags          = local.tags

  lifecycle {
    precondition {
      condition     = var.subnet_id == null || length(var.security_group_ids) > 0
      error_message = "The security_group_ids must name at least one security group when subnet_id is set."
    }
  }

  # An instance launched before the policies are attached cannot register with
  # Systems Manager, and the build times out waiting for it.
  depends_on = [
    aws_iam_role_policy_attachment.instance,
    aws_iam_role_policy.instance,
    aws_iam_role_policy.logs,
  ]
}
