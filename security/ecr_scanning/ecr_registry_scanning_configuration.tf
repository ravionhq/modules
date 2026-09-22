data "aws_regions" "enabled" {
  all_regions = false
}

# Registry scanning is a singleton per account and Region. Keep its ownership
# separate from repository/service modules so their applies cannot overwrite it.
resource "aws_ecr_registry_scanning_configuration" "this" {
  for_each = toset(var.regions)

  region    = each.key
  scan_type = "BASIC"

  rule {
    scan_frequency = "SCAN_ON_PUSH"

    repository_filter {
      filter      = "*"
      filter_type = "WILDCARD"
    }
  }

  lifecycle {
    precondition {
      condition     = contains(data.aws_regions.enabled.names, each.key)
      error_message = "Region ${each.key} is not enabled for this AWS account. Opt in to the Region (or remove it from regions) before configuring ECR scanning there."
    }
  }
}
