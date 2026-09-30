data "aws_region" "current" {}

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

################################################################################
# IAM Identity Center
#
# User and group names are listed and matched here rather than looked up one
# by one, so a plan needs only list permissions on the identity store.
################################################################################

data "aws_ssoadmin_instances" "this" {
  count = local.identity_center ? 1 : 0

  region = local.identity_center_region
}

data "aws_identitystore_users" "this" {
  count = local.identity_center && length(local.user_names) > 0 ? 1 : 0

  region            = local.identity_center_region
  identity_store_id = one(data.aws_ssoadmin_instances.this[0].identity_store_ids)
}

data "aws_identitystore_groups" "this" {
  count = local.identity_center && length(local.group_names) > 0 ? 1 : 0

  region            = local.identity_center_region
  identity_store_id = one(data.aws_ssoadmin_instances.this[0].identity_store_ids)
}
