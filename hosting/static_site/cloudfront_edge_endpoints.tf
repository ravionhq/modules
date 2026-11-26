################################################################################
# Edge endpoints
#
# Each var.edge_endpoints entry is a path answered by caller-supplied
# CloudFront Function code. The function is the only viewer-request function
# on that path's cache behavior (see local.edge_endpoint_behaviors), so a
# function that returns a response answers at the edge and never reaches S3.
#
# CloudFront adds its generated request headers (CloudFront-Viewer-Country and
# the like) to a request when a policy on the behavior lists them, so an
# endpoint that lists cloudfront_headers gets its own origin request policy.
################################################################################

resource "aws_cloudfront_function" "edge_endpoint" {
  for_each = local.edge_endpoints

  provider = aws.us_east_1

  name    = each.value.resource_name
  runtime = "cloudfront-js-2.0"
  comment = "${var.name} edge endpoint ${each.key}"
  publish = true
  code    = each.value.code

  # Order distribution detachment before deleting the function.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudfront_origin_request_policy" "edge_endpoint" {
  for_each = { for path_pattern, endpoint in local.edge_endpoints : path_pattern => endpoint if length(endpoint.cloudfront_headers) > 0 }

  provider = aws.us_east_1

  name    = each.value.resource_name
  comment = "${var.name} edge endpoint ${each.key} request headers"

  cookies_config {
    cookie_behavior = "none"
  }

  headers_config {
    header_behavior = "whitelist"

    headers {
      items = each.value.cloudfront_headers
    }
  }

  query_strings_config {
    query_string_behavior = "none"
  }

  # Order distribution detachment before deleting the policy.
  lifecycle {
    create_before_destroy = true
  }
}
