locals {
  region = coalesce(var.region, data.aws_region.current.region)
}

################################################################################
# Local Values
################################################################################

locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "containers/ecr"
  }

  tags = merge(local.default_tags, var.tags)

  # Lifecycle policy resolution: explicit JSON > default helper > none.
  default_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images older than ${var.untagged_image_expiry_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_image_expiry_days
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep only the last ${var.max_tagged_image_count} tagged images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.max_tagged_image_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })

  effective_lifecycle_policy = (
    var.lifecycle_policy != null
    ? var.lifecycle_policy
    : (var.default_lifecycle_policy_enabled ? local.default_lifecycle_policy : null)
  )

  create_lifecycle_policy = local.effective_lifecycle_policy != null

  # Repository policy resolution: explicit JSON > principals helper > none.
  generated_policy_statements = concat(
    length(var.allowed_pull_principal_arns) > 0 ? [{
      Sid    = "AllowPull"
      Effect = "Allow"
      Principal = {
        AWS = var.allowed_pull_principal_arns
      }
      Action = [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability",
      ]
    }] : [],
    length(var.allowed_push_principal_arns) > 0 ? [{
      Sid    = "AllowPush"
      Effect = "Allow"
      Principal = {
        AWS = var.allowed_push_principal_arns
      }
      Action = [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
      ]
    }] : []
  )

  generated_repository_policy = length(local.generated_policy_statements) > 0 ? jsonencode({
    Version   = "2012-10-17"
    Statement = local.generated_policy_statements
  }) : null

  effective_repository_policy = (
    var.repository_policy != null
    ? var.repository_policy
    : local.generated_repository_policy
  )

  create_repository_policy = local.effective_repository_policy != null
}
