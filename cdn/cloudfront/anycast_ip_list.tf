locals {
  anycast_ip_list_id = var.anycast_ip_list_mode == "create" ? aws_cloudfront_anycast_ip_list.this[0].id : (
    var.anycast_ip_list_mode == "existing" ? try(trimspace(var.anycast_ip_list_id), null) : null
  )
}

resource "aws_cloudfront_anycast_ip_list" "this" {
  count = var.anycast_ip_list_mode == "create" ? 1 : 0

  name     = "${substr(var.name, 0, 54)}-static-${var.anycast_ip_count}"
  ip_count = var.anycast_ip_count
  tags     = local.tags

  lifecycle {
    create_before_destroy = true
  }
}
