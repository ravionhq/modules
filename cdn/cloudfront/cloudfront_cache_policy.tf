resource "aws_cloudfront_cache_policy" "accept_header" {
  count = var.accept_header_cache_policy_creation_enabled ? 1 : 0

  name    = "${var.name}-accept-header"
  comment = "Use origin cache control headers and include Accept in the cache key"

  min_ttl     = 0
  default_ttl = 0
  max_ttl     = 31536000

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true

    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "whitelist"
      headers {
        items = ["Accept"]
      }
    }

    query_strings_config {
      query_string_behavior = "all"
    }
  }
}
