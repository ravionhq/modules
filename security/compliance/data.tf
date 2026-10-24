data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}

# Both services require the selected Regions to be enabled for the account.
data "aws_regions" "enabled" {
  all_regions = false
}
