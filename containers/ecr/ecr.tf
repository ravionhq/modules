################################################################################
# ECR Repository
################################################################################

resource "aws_ecr_repository" "this" {
  region               = var.region
  name                 = var.name
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete_enabled

  image_scanning_configuration {
    scan_on_push = var.image_scan_on_push_enabled
  }

  encryption_configuration {
    encryption_type = var.encryption_type
    kms_key         = var.encryption_type == "KMS" ? var.kms_key_arn : null
  }

  tags = merge(local.tags, {
    Name = var.name
  })

  lifecycle {
    precondition {
      condition     = var.encryption_type != "KMS" || var.kms_key_arn == null || can(regex("^arn:aws:kms:", var.kms_key_arn))
      error_message = "When encryption_type is KMS, kms_key_arn must be either null (for AWS-managed KMS) or a valid KMS key ARN."
    }
  }
}

################################################################################
# Lifecycle Policy
################################################################################

resource "aws_ecr_lifecycle_policy" "this" {
  count = local.create_lifecycle_policy ? 1 : 0

  region     = var.region
  repository = aws_ecr_repository.this.name
  policy     = local.effective_lifecycle_policy
}

################################################################################
# Repository Policy
################################################################################

resource "aws_ecr_repository_policy" "this" {
  count = local.create_repository_policy ? 1 : 0

  region     = var.region
  repository = aws_ecr_repository.this.name
  policy     = local.effective_repository_policy
}
