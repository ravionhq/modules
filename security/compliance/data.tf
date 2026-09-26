data "aws_caller_identity" "current" {}

# Both services require the selected Regions to be enabled for the account.
data "aws_regions" "enabled" {
  all_regions = false
}
