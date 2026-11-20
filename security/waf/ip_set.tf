################################################################################
# IP sets for ip_allow_list and ip_block_list (one per address family)
################################################################################

resource "aws_wafv2_ip_set" "this" {
  for_each = local.ip_sets

  region = local.region

  name               = "${substr(var.name, 0, 117)}-${each.key}"
  scope              = local.scope
  ip_address_version = each.value.version
  addresses          = each.value.addresses
  tags               = local.tags
}
