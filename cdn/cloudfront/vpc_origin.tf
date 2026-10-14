# CloudFront rejects updates to a VPC origin while a distribution uses it, so
# any endpoint change replaces the VPC origin instead of updating it.
resource "terraform_data" "vpc_origin_endpoint" {
  for_each = local.vpc_origin_endpoints

  input = each.value
}

resource "aws_cloudfront_vpc_origin" "this" {
  for_each = local.vpc_origin_endpoints

  vpc_origin_endpoint_config {
    name                   = local.vpc_origin_names[each.key]
    arn                    = each.value.arn
    http_port              = each.value.http_port
    https_port             = each.value.https_port
    origin_protocol_policy = each.value.origin_protocol_policy

    origin_ssl_protocols {
      items    = each.value.origin_ssl_protocols
      quantity = length(each.value.origin_ssl_protocols)
    }
  }

  tags = merge(local.tags, { Name = each.value.base_name })

  # Create the replacement first, move the distribution to it, then delete the
  # old VPC origin once no distribution uses it.
  lifecycle {
    create_before_destroy = true
    replace_triggered_by  = [terraform_data.vpc_origin_endpoint[each.key]]
  }
}
