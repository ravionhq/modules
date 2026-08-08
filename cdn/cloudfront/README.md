# AWS CloudFront

Creates and manages AWS CloudFront distributions with support for multiple distributions (domain groups), multiple origin types, modern cache policies, Origin Access Control (OAC) for S3, WAF integration, and optional access logging.

## Features

- **Multiple Distributions**: Create multiple CloudFront distributions sharing the same origins and cache behaviors, each with its own custom domains and SSL certificate
- **Multiple Origins**: Support for S3 and custom (ALB, API Gateway, HTTP) origins with per-origin configuration
- **Modern Cache Policies**: Uses cache policies and origin request policies (no legacy `forwarded_values`)
- **Origin Access Control**: Automatic OAC creation for S3 origins (recommended over legacy OAI)
- **Signed URL Enforcement**: Trusted key group wiring for signed URLs and signed cookies
- **SSL/TLS**: Custom ACM certificates with configurable minimum TLS version, SNI support
- **WAF Integration**: Associate a WAFv2 Web ACL (global scope) for edge protection
- **Access Logging**: On by default via CloudFront standard logging v2 into a module-managed CloudWatch Logs group (us-east-1); legacy S3 delivery with lifecycle management and per-distribution log prefixes remains available
- **Monitoring**: Optional CloudFront additional metrics subscription for cache hit rate, origin latency, and per-status error rates
- **Edge Functions**: Support for CloudFront Functions and Lambda@Edge associations
- **Edge Redirects**: Ordered URL-pattern redirects with named segments, catch-all paths, and optional query preservation
- **Custom Error Pages**: Configurable error response handling with custom pages
- **Geo Restrictions**: Whitelist or blacklist countries using ISO 3166-1-alpha-2 codes
- **HTTP/3 Support**: HTTP/2 and HTTP/3 enabled by default
- **Origin Shield**: Optional regional caching layer to reduce origin load

## Usage

### Basic S3 Static Website

```hcl
module "cdn" {
  source = "git::https://github.com/user/ravion-modules.git//cdn/cloudfront?ref=v1.0.0"

  name = "my-website"

  distributions = {
    main = {}
  }

  origins = [
    {
      origin_id   = "s3-assets"
      domain_name = "my-bucket.s3.us-east-1.amazonaws.com"
      s3_origin_enabled   = true
    }
  ]

  default_cache_behavior = {
    target_origin_id       = "s3-assets"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized
  }

  default_root_object = "index.html"
}
```

### ALB Origin with HTTPS

```hcl
module "cdn" {
  source = "git::https://github.com/user/ravion-modules.git//cdn/cloudfront?ref=v1.0.0"

  name = "my-api"

  distributions = {
    main = {
      aliases             = ["api.example.com"]
      acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc-123"
    }
  }

  origins = [
    {
      origin_id              = "alb"
      domain_name            = "my-alb-123456.us-east-1.elb.amazonaws.com"
      origin_protocol_policy = "https-only"
    }
  ]

  default_cache_behavior = {
    target_origin_id       = "alb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3" # AllViewer
  }
}
```

### Private S3 Origin with Signed URLs

```hcl
module "cdn" {
  source = "git::https://github.com/user/ravion-modules.git//cdn/cloudfront?ref=v1.0.0"

  name = "private-attachments"

  distributions = {
    main = {}
  }

  origins = [
    {
      origin_id         = "attachments"
      domain_name       = "private-attachments.s3.us-east-1.amazonaws.com"
      s3_origin_enabled = true
    }
  ]

  default_cache_behavior = {
    target_origin_id       = "attachments"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized
    trusted_key_groups     = ["K123456789EXAMPLE"]
  }
}
```

For private S3 origins, the bucket policy must allow the CloudFront service principal to read objects, scoped to the distribution ARN. If the bucket is managed by `storage/s3`, use the `cloudfront_oac_read` policy template with `cloudfront_distribution_arns = [module.cdn.distribution_arn]`.

### Multi-Origin (S3 + ALB) with Ordered Cache Behaviors

```hcl
module "cdn" {
  source = "git::https://github.com/user/ravion-modules.git//cdn/cloudfront?ref=v1.0.0"

  name = "my-app"

  distributions = {
    main = {
      aliases             = ["app.example.com"]
      acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc-123"
    }
  }

  origins = [
    {
      origin_id   = "s3-assets"
      domain_name = "my-assets.s3.us-east-1.amazonaws.com"
      s3_origin_enabled   = true
    },
    {
      origin_id              = "alb-api"
      domain_name            = "my-alb-123456.us-east-1.elb.amazonaws.com"
      origin_protocol_policy = "https-only"
    }
  ]

  default_cache_behavior = {
    target_origin_id       = "s3-assets"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized
  }

  ordered_cache_behaviors = [
    {
      path_pattern           = "/api/*"
      target_origin_id       = "alb-api"
      viewer_protocol_policy = "https-only"
      allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled
      origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3" # AllViewer
    }
  ]

  default_root_object = "index.html"
}
```

### Multiple Distributions with Different Domain Groups

```hcl
module "cdn" {
  source = "git::https://github.com/user/ravion-modules.git//cdn/cloudfront?ref=v1.0.0"

  name = "my-app"

  distributions = {
    production = {
      aliases             = ["app.example.com", "www.example.com"]
      acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/prod-cert"
    }
    staging = {
      aliases             = ["staging.example.com"]
      acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/staging-cert"
    }
  }

  origins = [
    {
      origin_id   = "s3-assets"
      domain_name = "my-assets.s3.us-east-1.amazonaws.com"
      s3_origin_enabled   = true
    }
  ]

  default_cache_behavior = {
    target_origin_id       = "s3-assets"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized
  }
}
```

### Production with WAF and Logging

```hcl
module "cdn" {
  source = "git::https://github.com/user/ravion-modules.git//cdn/cloudfront?ref=v1.0.0"

  name = "my-app"

  distributions = {
    main = {
      aliases             = ["app.example.com"]
      acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc-123"
    }
  }

  origins = [
    {
      origin_id              = "alb"
      domain_name            = "my-alb-123456.us-east-1.elb.amazonaws.com"
      origin_protocol_policy = "https-only"
    }
  ]

  default_cache_behavior = {
    target_origin_id       = "alb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3" # AllViewer
  }

  # WAF
  web_acl_id = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/my-acl/abc-123"

  # Logging (CloudWatch Logs is the default; opt into legacy S3 delivery)
  logging_enabled                 = true
  logging_destination             = "s3"
  logging_bucket_creation_enabled = true
  logging_prefix                  = "cloudfront/"

  tags = {
    Environment = "production"
  }
}
```

### With Custom Error Responses

```hcl
module "cdn" {
  source = "git::https://github.com/user/ravion-modules.git//cdn/cloudfront?ref=v1.0.0"

  name = "my-spa"

  distributions = {
    main = {
      aliases             = ["app.example.com"]
      acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc-123"
    }
  }

  origins = [
    {
      origin_id   = "s3-assets"
      domain_name = "my-bucket.s3.us-east-1.amazonaws.com"
      s3_origin_enabled   = true
    }
  ]

  default_cache_behavior = {
    target_origin_id       = "s3-assets"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized
  }

  custom_error_responses = [
    {
      error_code            = 403
      response_code         = 200
      response_page_path    = "/index.html"
      error_caching_min_ttl = 10
    },
    {
      error_code            = 404
      response_code         = 200
      response_page_path    = "/index.html"
      error_caching_min_ttl = 10
    }
  ]

  default_root_object = "index.html"
}
```

### With Geo Restrictions

```hcl
module "cdn" {
  source = "git::https://github.com/user/ravion-modules.git//cdn/cloudfront?ref=v1.0.0"

  name = "my-app"

  distributions = {
    main = {
      aliases             = ["app.example.com"]
      acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc-123"
    }
  }

  origins = [
    {
      origin_id   = "s3-assets"
      domain_name = "my-bucket.s3.us-east-1.amazonaws.com"
      s3_origin_enabled   = true
    }
  ]

  default_cache_behavior = {
    target_origin_id       = "s3-assets"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized
  }

  # Only allow US and Canada
  geo_restriction_type      = "whitelist"
  geo_restriction_locations = ["US", "CA"]
}
```

### With Additional CloudFront Metrics

```hcl
module "cdn" {
  source = "git::https://github.com/user/ravion-modules.git//cdn/cloudfront?ref=v1.0.0"

  name = "my-app"

  distributions = {
    main = {}
  }

  origins = [
    {
      origin_id              = "alb"
      domain_name            = "my-alb-123456.us-east-1.elb.amazonaws.com"
      origin_protocol_policy = "https-only"
    }
  ]

  default_cache_behavior = {
    target_origin_id       = "alb"
    viewer_protocol_policy = "redirect-to-https"
  }

  additional_metrics_enabled = true
}
```

CloudFront publishes default distribution metrics at no additional CloudWatch metric cost. Enabling `additional_metrics_enabled` creates a monitoring subscription for each distribution and turns on all 8 CloudFront additional metrics: `CacheHitRate`, `OriginLatency`, `401ErrorRate`, `403ErrorRate`, `404ErrorRate`, `502ErrorRate`, `503ErrorRate`, and `504ErrorRate`. CloudWatch bills these as a flat per-metric monthly charge per distribution, regardless of request volume.

### Hostname Redirect with Path Preservation

Redirect rules run at viewer request time before CloudFront contacts an origin. Rules are evaluated in order and the first match wins. The managed redirect function is attached to the default behavior and every ordered behavior so redirects cover every request path.

```hcl
module "cdn" {
  source = "git::https://github.com/ravionhq/modules.git//cdn/cloudfront?ref=rvn-cloudfront@0.3.0"

  name = "marketing"

  distributions = {
    main = {
      aliases             = ["www.example.com", "docs.example.com"]
      acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc-123"
    }
  }

  origins = [
    {
      origin_id              = "website"
      domain_name            = "website-origin.example.com"
      origin_protocol_policy = "https-only"
    }
  ]

  default_cache_behavior = {
    target_origin_id       = "website"
    viewer_protocol_policy = "redirect-to-https"
  }

  redirect_rules = [
    {
      source                = "https://docs.example.com/:path*"
      destination           = "https://www.example.com/docs/:path*"
      preserve_query_string = true
      status_code           = 308
    }
  ]
}
```

This redirects `https://docs.example.com/quickstart?source=nav` to `https://www.example.com/docs/quickstart?source=nav`. A `:name` parameter captures one path segment, while a final `:name*` captures zero or more remaining segments. Parameters can be reordered, omitted, or repeated in the destination. A path-only source matches every distribution alias, and a path-only destination keeps the request host. Redirects always use HTTPS.

Enabling `redirect_rules` is incompatible with caller-supplied CloudFront Function or Lambda@Edge `viewer-request` associations because CloudFront allows only one viewer-request association per behavior.

The module prevents a rule from redirecting back into its own source pattern. It cannot detect cycles spanning multiple independently matching rules, so review rule ordering and destinations when defining bidirectional or multi-domain redirects.

#### Avoid Overlapping Same-Host Rules

Before returning a redirect, the edge function checks whether the destination would match the same source pattern on the same host. If it would, the function skips that rule and evaluates the next rule. If no later rule matches, CloudFront sends the original request to the configured origin. This prevents an infinite loop, but it can make an overlapping rule appear inactive.

This rule does not redirect because `/docs/guide` still matches the broad `/:path*` source and would become `/docs/docs/guide` on the next request:

```hcl
redirect_rules = [
  {
    source      = "https://d111111abcdef8.cloudfront.net/:path*"
    destination = "https://d111111abcdef8.cloudfront.net/docs/:path*"
  }
]
```

Use different source and destination hosts when migrating a domain:

```hcl
redirect_rules = [
  {
    source      = "https://docs.example.com/:path*"
    destination = "https://www.example.com/docs/:path*"
  }
]
```

For same-host testing, use a source namespace that does not overlap the destination:

```hcl
redirect_rules = [
  {
    source      = "https://d111111abcdef8.cloudfront.net/old/:path*"
    destination = "https://d111111abcdef8.cloudfront.net/docs/:path*"
  }
]
```

The same-host example redirects `/old/guide` to `/docs/guide`. To redirect only the root, use the exact source `https://d111111abcdef8.cloudfront.net` without a path parameter. Redirect patterns do not currently support exclusions such as "all paths except `/docs`".

## Requirements

| Name               | Version   |
| ------------------ | --------- |
| opentofu/terraform | >= 1.10.0 |
| aws                | >= 6.0    |

## Inputs

### General

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name prefix for all resources created by this module. | `string` | n/a | yes |
| tags | A map of tags to assign to all resources. | `map(string)` | `{}` | no |

### Distributions

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| distributions | A map of CloudFront distributions to create. Each key is a distribution identifier. | `map(object({...}))` | n/a | yes |
| distributions[].aliases | CNAMEs for this distribution. | `list(string)` | `[]` | no |
| distributions[].acm_certificate_arn | ACM certificate ARN for this distribution's domains. | `string` | `null` | no |
| distributions[].comment | Distribution-specific comment. | `string` | `"${name}-${key}"` | no |
| distributions[].enabled | Whether this distribution accepts requests. | `bool` | `true` | no |

### Origins

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| origins | A list of origin configurations for the CloudFront distribution. | `list(object({...}))` | n/a | yes |
| origins[].origin_id | Unique identifier for the origin. | `string` | n/a | yes |
| origins[].domain_name | Origin domain name. | `string` | n/a | yes |
| origins[].origin_path | Path prefix appended to the origin domain name. | `string` | `null` | no |
| origins[].origin_protocol_policy | Protocol policy for custom origins: `http-only`, `https-only`, `match-viewer`. | `string` | `"https-only"` | no |
| origins[].http_port | HTTP port for the origin. | `number` | `80` | no |
| origins[].https_port | HTTPS port for the origin. | `number` | `443` | no |
| origins[].origin_ssl_protocols | SSL/TLS protocols for the origin. | `list(string)` | `["TLSv1.2"]` | no |
| origins[].origin_keepalive_timeout | Keep-alive timeout in seconds. | `number` | `null` | no |
| origins[].origin_read_timeout | Read timeout in seconds. | `number` | `null` | no |
| origins[].origin_access_control_id | Override to use an externally-managed OAC. | `string` | `null` | no |
| origins[].connection_attempts | Number of connection attempts (1-3). | `number` | `null` | no |
| origins[].connection_timeout | Connection timeout in seconds (1-10). | `number` | `null` | no |
| origins[].custom_headers | List of custom headers to send to the origin. | `list(object({name, value}))` | `[]` | no |
| origins[].origin_shield | Origin Shield configuration. | `object({enabled, origin_shield_region})` | `null` | no |
| origins[].s3_origin_enabled | Whether this is an S3 origin (creates OAC). | `bool` | `false` | no |

### Default Cache Behavior

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| default_cache_behavior | The default cache behavior configuration. | `object({...})` | n/a | yes |
| default_cache_behavior.target_origin_id | Origin ID for the default cache behavior. | `string` | n/a | yes |
| default_cache_behavior.viewer_protocol_policy | Viewer protocol policy: `allow-all`, `https-only`, `redirect-to-https`. | `string` | n/a | yes |
| default_cache_behavior.allowed_methods | HTTP methods to allow. | `list(string)` | `["GET", "HEAD"]` | no |
| default_cache_behavior.cached_methods | HTTP methods to cache. | `list(string)` | `["GET", "HEAD"]` | no |
| default_cache_behavior.compression_enabled | Whether to compression_enabled content. | `bool` | `true` | no |
| default_cache_behavior.cache_policy_id | Cache policy ID. | `string` | `null` | no |
| default_cache_behavior.origin_request_policy_id | Origin request policy ID. | `string` | `null` | no |
| default_cache_behavior.response_headers_policy_id | Response headers policy ID. | `string` | `null` | no |
| default_cache_behavior.trusted_key_groups | CloudFront key group IDs trusted for signed URLs or signed cookies. | `list(string)` | `[]` | no |
| default_cache_behavior.function_associations | CloudFront Function associations. | `list(object({event_type, function_arn}))` | `[]` | no |
| default_cache_behavior.lambda_function_associations | Lambda@Edge associations. | `list(object({event_type, lambda_arn, body_inclusion_enabled}))` | `[]` | no |
| default_cache_behavior.realtime_log_config_arn | Real-time log configuration ARN. | `string` | `null` | no |
| accept_header_cache_policy_creation_enabled | Whether to create and use a module-managed default cache policy that includes the `Accept` header in the cache key. Cannot be combined with `default_cache_behavior.cache_policy_id`. | `bool` | `false` | no |

### Ordered Cache Behaviors

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| ordered_cache_behaviors | An ordered list of cache behaviors with path patterns. Same fields as default_cache_behavior plus `path_pattern`. | `list(object({...}))` | `[]` | no |

### Edge Redirects

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| redirect_rules | Ordered URL-pattern redirects handled before CloudFront contacts an origin. | `list(object({...}))` | `[]` | no |
| redirect_rules[].source | Absolute HTTPS URL or host-agnostic path containing literal segments, `:name` parameters, and optionally one final `:name*` catch-all. | `string` | n/a | yes |
| redirect_rules[].destination | Absolute HTTPS URL or host-agnostic path using parameters captured by the source. | `string` | n/a | yes |
| redirect_rules[].preserve_query_string | Append query parameters to the redirect location. | `bool` | `false` | no |
| redirect_rules[].redirect_non_read_methods | Redirect methods other than GET and HEAD. | `bool` | `false` | no |
| redirect_rules[].status_code | Redirect status: `301`, `302`, `307`, or `308`. | `number` | `308` | no |

### Distribution Settings

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| price_class | Price class: `PriceClass_100`, `PriceClass_200`, `PriceClass_All`. | `string` | `"PriceClass_100"` | no |
| http_version | Maximum HTTP version: `http1.1`, `http2`, `http2and3`. | `string` | `"http2and3"` | no |
| ipv6_enabled | Whether IPv6 is enabled. | `bool` | `true` | no |
| default_root_object | Object returned for root URL requests (e.g., `index.html`). | `string` | `null` | no |
| retain_on_delete_enabled | Retain (disable) the distribution on delete instead of removing it. | `bool` | `false` | no |
| deployment_wait_enabled | Wait for the distribution to deploy before completing. | `bool` | `true` | no |
| additional_metrics_enabled | Enable CloudFront additional metrics in CloudWatch. This enables all 8 additional metrics for each distribution and incurs a fixed per-metric CloudWatch charge. | `bool` | `false` | no |

### SSL/TLS

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| minimum_protocol_version | Minimum TLS version for viewer connections. | `string` | `"TLSv1.2_2021"` | no |
| ssl_support_method | HTTPS serving method: `sni-only`, `vip`, `static-ip`. | `string` | `"sni-only"` | no |

### Restrictions

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| geo_restriction_type | Geo restriction type: `none`, `whitelist`, `blacklist`. | `string` | `"none"` | no |
| geo_restriction_locations | ISO 3166-1-alpha-2 country codes for geo restriction. | `list(string)` | `[]` | no |

### Custom Error Responses

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| custom_error_responses | Custom error response configurations. | `list(object({...}))` | `[]` | no |
| custom_error_responses[].error_code | HTTP error code (400, 403, 404, 405, 414, 416, 500, 501, 502, 503, 504). | `number` | n/a | yes |
| custom_error_responses[].response_code | HTTP response code to return. | `number` | `null` | no |
| custom_error_responses[].response_page_path | Path to the custom error page. | `string` | `null` | no |
| custom_error_responses[].error_caching_min_ttl | Minimum TTL in seconds for caching this error. | `number` | `null` | no |

### WAF

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| web_acl_id | WAFv2 Web ACL ARN (global scope) to associate with the distribution. | `string` | `null` | no |

### Logging

Access logging is enabled by default. The default destination is CloudWatch Logs: CloudFront standard logging v2 delivers access logs into a module-managed log group `/aws/cloudfront/<name>` via a per-distribution delivery source, a shared delivery destination (JSON output), and a per-distribution delivery. CloudFront is a global service, so the whole delivery chain is pinned to `us-east-1` with the per-resource `region` argument (AWS provider >= 6.0). Set `logging_destination = "s3"` for legacy standard logging to an S3 bucket, or `logging_enabled = false` to turn logging off.

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| logging_enabled | Enable CloudFront access logging. Defaults to true with CloudWatch Logs delivery; see `logging_destination`. | `bool` | `true` | no |
| logging_destination | Where access logs are delivered: `cloudwatch` (standard logging v2 into a module-managed CloudWatch Logs group) or `s3` (legacy standard logging). | `string` | `"cloudwatch"` | no |
| logging_bucket_domain_name | Domain name of an existing S3 bucket for logs. Only applies when `logging_destination = "s3"`. | `string` | `null` | no |
| logging_prefix | Base S3 key prefix for log files. Each distribution logs under `<prefix><key>/`. Only applies when `logging_destination = "s3"`. | `string` | `""` | no |
| logging_cookies_enabled | Include cookies in access logs. Only applies when `logging_destination = "s3"`. | `bool` | `false` | no |
| logging_bucket_creation_enabled | Create a new S3 bucket for logging. Only applies when `logging_destination = "s3"`. | `bool` | `false` | no |
| logging_bucket_retention_days | Days to retain logs: CloudWatch log group retention (`cloudwatch`, must be a valid CloudWatch retention value) or S3 lifecycle expiry on the module-created bucket (`s3`). | `number` | `90` | no |

### Origin Access Control

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| origin_access_control_creation_enabled | Create OAC resources for S3 origins. | `bool` | `true` | no |
| origin_access_control_origin_type | OAC origin type: `s3`, `mediastore`, `mediapackagev2`, `lambda`. | `string` | `"s3"` | no |
| origin_access_control_signing_behavior | OAC signing behavior: `always`, `never`, `no-override`. | `string` | `"always"` | no |
| origin_access_control_signing_protocol | OAC signing protocol. | `string` | `"sigv4"` | no |

## Outputs

| Name | Description |
|------|-------------|
| cache_policy_id | The ID of the cache policy attached to the default behavior, including the module-managed Accept-aware policy when enabled. |
| distribution_ids | A map of distribution key to CloudFront distribution ID. |
| distribution_arns | A map of distribution key to CloudFront distribution ARN. |
| distribution_domain_names | A map of distribution key to CloudFront distribution domain name. |
| distribution_hosted_zone_ids | A map of distribution key to Route 53 zone ID for alias records. |
| distribution_statuses | A map of distribution key to current distribution status. |
| distribution_etags | A map of distribution key to current distribution ETag. |
| distribution_id | The distribution ID when exactly one distribution is created (null otherwise). |
| distribution_arn | The distribution ARN when exactly one distribution is created (null otherwise). |
| distribution_domain_name | The distribution domain name when exactly one distribution is created (null otherwise). |
| distribution_hosted_zone_id | The Route 53 hosted zone ID when exactly one distribution is created (null otherwise). |
| redirect_function_arn | The managed redirect function ARN (null when redirects are disabled). |
| redirect_function_name | The managed redirect function name (null when redirects are disabled). |
| origin_access_control_ids | A map of origin_id to OAC ID for S3 origins. |
| logging_bucket_id | The ID of the logging S3 bucket (null if not created). |
| logging_bucket_arn | The ARN of the logging S3 bucket (null if not created). |
| logging_bucket_domain_name | The domain name of the logging S3 bucket (null if not created). |
| access_log_group_name | Name of the CloudWatch Logs group receiving CloudFront access logs (null unless CloudWatch logging is active). |
| access_log_group_arn | ARN of the CloudWatch Logs access-log group (null unless CloudWatch logging is active). |

## Architecture

### Overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                          AWS CloudFront Module                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                     CloudFront Distributions                           │  │
│  │  • One per entry in var.distributions (for_each)                      │  │
│  │  • Per-distribution: aliases, ACM cert, comment, enabled              │  │
│  │  • Shared: origins, cache behaviors, settings, WAF, restrictions      │  │
│  │  • HTTP/2 and HTTP/3 by default                                       │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                     │                                         │
│                                     ▼                                         │
│  ┌──────────────────────┐  ┌──────────────────────┐  ┌────────────────────┐  │
│  │   Origins            │  │   Cache Behaviors    │  │   Viewer Cert      │  │
│  │  • S3 (with OAC)     │  │  • Default behavior  │  │  • ACM certificate │  │
│  │  • ALB / Custom HTTP │  │  • Ordered behaviors  │  │  • TLSv1.2_2021   │  │
│  │  • Origin Shield     │  │  • Cache policies     │  │  • SNI-only        │  │
│  └──────────────────────┘  └──────────────────────┘  └────────────────────┘  │
│                                                                               │
│  ┌──────────────────────┐  ┌──────────────────────┐  ┌────────────────────┐  │
│  │   Origin Access Ctrl │  │   Access Logging     │  │   WAF / Restrict   │  │
│  │  • Per S3 origin     │  │  • Optional S3 bucket│  │  • WAFv2 Web ACL   │  │
│  │  • SigV4 signing     │  │  • Per-dist prefixes │  │  • Geo restrictions│  │
│  │  • Shared across all │  │  • Lifecycle mgmt    │  │  • Error responses │  │
│  └──────────────────────┘  └──────────────────────┘  └────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Detailed Module Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                       CDN/CLOUDFRONT TERRAFORM MODULE                                                │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                                 INPUT VARIABLES                                                        ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌─────────────────────────────────────────┐  ║
║  │       GENERAL               │   │       DISTRIBUTIONS             │   │            ORIGINS                      │  ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤   ├─────────────────────────────────────────┤  ║
║  │ • name (required)           │   │ • distributions (required)      │   │ • origins (required)                    │  ║
║  │ • tags                      │   │   └─ aliases                    │   │   └─ origin_id, domain_name             │  ║
║  └─────────────────────────────┘   │   └─ acm_certificate_arn        │   │   └─ s3_origin_enabled, origin_path             │  ║
║                                    │   └─ comment, enabled           │   │   └─ protocol, ports, timeouts          │  ║
║                                    └─────────────────────────────────┘   │   └─ custom_headers, origin_shield      │  ║
║                                                                          └─────────────────────────────────────────┘  ║
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌─────────────────────────────────────────┐  ║
║  │  DEFAULT CACHE BEHAVIOR     │   │  ORDERED CACHE BEHAVIORS        │   │      DISTRIBUTION SETTINGS              │  ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤   ├─────────────────────────────────────────┤  ║
║  │ • target_origin_id          │   │ • path_pattern                  │   │ • price_class                           │  ║
║  │ • viewer_protocol_policy    │   │ • target_origin_id              │   │ • http_version                          │  ║
║  │ • allowed/cached_methods    │   │ • viewer_protocol_policy        │   │ • ipv6_enabled                       │  ║
║  │ • cache_policy_id           │   │ • cache_policy_id               │   │ • default_root_object                   │  ║
║  │ • origin_request_policy_id  │   │ • origin_request_policy_id      │   │ • retain_on_delete_enabled                      │  ║
║  │ • function_associations     │   │ • function_associations         │   │ • deployment_wait_enabled                   │  ║
║  │ • lambda_fn_associations    │   │ • lambda_fn_associations        │   └─────────────────────────────────────────┘  ║
║  └─────────────────────────────┘   └─────────────────────────────────┘                                                 ║
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌─────────────────────────────────────────┐  ║
║  │       SSL/TLS               │   │      RESTRICTIONS               │   │          WAF & ERRORS                   │  ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤   ├─────────────────────────────────────────┤  ║
║  │ • minimum_protocol_version  │   │ • geo_restriction_type          │   │ • web_acl_id                            │  ║
║  │ • ssl_support_method        │   │ • geo_restriction_locations     │   │ • custom_error_responses                │  ║
║  └─────────────────────────────┘   └─────────────────────────────────┘   └─────────────────────────────────────────┘  ║
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐                                                 ║
║  │       LOGGING               │   │   ORIGIN ACCESS CONTROL         │                                                 ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤                                                 ║
║  │ • logging_enabled            │   │ • origin_access_control_creation_enabled  │                                                 ║
║  │ • logging_bucket_creation_enabled     │   │ • oac_origin_type               │                                                 ║
║  │ • logging_bucket_domain_name│   │ • oac_signing_behavior          │                                                 ║
║  │ • logging_prefix            │   │ • oac_signing_protocol          │                                                 ║
║  │ • logging_cookies_enabled   │   └─────────────────────────────────┘                                                 ║
║  │ • logging_bucket_retention  │                                                                                       ║
║  └─────────────────────────────┘                                                                                       ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
                                                         │
                                                         ▼
╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                              TERRAFORM RESOURCES                                                       ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║    ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────┐    ║
║    │                           aws_cloudfront_origin_access_control.this                                          │    ║
║    │  • for_each over S3 origins (where s3_origin_enabled = true)                                                        │    ║
║    │  • SigV4 signing, configurable behavior and origin type                                                     │    ║
║    └─────────────────────────────────────────────────────────────────────────────────────────────────────────────┘    ║
║                                                           │                                                            ║
║                                                           ▼                                                            ║
║    ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────┐    ║
║    │                              aws_cloudfront_distribution.this                                                 │    ║
║    │                       (for_each = var.distributions — CORE RESOURCE)                                         │    ║
║    ├─────────────────────────────────────────────────────────────────────────────────────────────────────────────┤    ║
║    │                                                                                                              │    ║
║    │  Per-distribution: enabled, comment, aliases, acm_certificate_arn, logging prefix, tags                     │    ║
║    │  Shared: origins, default_cache_behavior, ordered_cache_behaviors, price_class, http_version, WAF           │    ║
║    │                                                                                                              │    ║
║    │  ┌─────────────────────┐  ┌────────────────────────┐  ┌──────────────────────────────────────────────────┐  │    ║
║    │  │ dynamic "origin"    │  │ default_cache_behavior  │  │ dynamic "ordered_cache_behavior"                │  │    ║
║    │  │  • S3 + custom      │  │  • Policies, methods    │  │  • Path-based routing                          │  │    ║
║    │  │  • OAC for S3       │  │  • Edge functions       │  │  • Per-path policies and functions             │  │    ║
║    │  │  • Origin Shield    │  └────────────────────────┘  └──────────────────────────────────────────────────┘  │    ║
║    │  └─────────────────────┘                                                                                    │    ║
║    │  ┌──────────────────────────────┐  ┌──────────────────────────┐  ┌────────────────────────────────────────┐  │    ║
║    │  │ dynamic "custom_error_resp"  │  │   viewer_certificate     │  │ dynamic "logging_config"              │  │    ║
║    │  │  • Custom error pages        │  │  • Default / ACM cert    │  │  • Per-distribution prefix            │  │    ║
║    │  │  • Cache TTL overrides       │  │  • TLS version, SNI      │  │  • Shared or created bucket           │  │    ║
║    │  └──────────────────────────────┘  └──────────────────────────┘  └────────────────────────────────────────┘  │    ║
║    │  ┌──────────────────────────┐                                                                                │    ║
║    │  │   restrictions           │                                                                                │    ║
║    │  │  • Geo whitelist/blacklist│                                                                               │    ║
║    │  └──────────────────────────┘                                                                                │    ║
║    └─────────────────────────────────────────────────────────────────────────────────────────────────────────────┘    ║
║                                                                                                                        ║
║    ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────┐    ║
║    │                                    Logging S3 Bucket (Optional)                                              │    ║
║    ├─────────────────────────────────────────────────────────────────────────────────────────────────────────────┤    ║
║    │  aws_s3_bucket.logging[0]                    (count = logging_bucket_creation_enabled ? 1 : 0)                        │    ║
║    │  aws_s3_bucket_ownership_controls.logging[0] (BucketOwnerPreferred for CF logging)                          │    ║
║    │  aws_s3_bucket_acl.logging[0]                (log-delivery-write)                                           │    ║
║    │  aws_s3_bucket_lifecycle_configuration[0]    (expiration after N days)                                       │    ║
║    └─────────────────────────────────────────────────────────────────────────────────────────────────────────────┘    ║
║                                                                                                                        ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
                                                         │
                                                         ▼
╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                                   OUTPUTS                                                              ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║  ┌─────────────────────────────────────────┐   ┌─────────────────────────────────────────┐                            ║
║  │     DISTRIBUTIONS (maps by key)         │   │      ORIGIN ACCESS CONTROL              │                            ║
║  ├─────────────────────────────────────────┤   ├─────────────────────────────────────────┤                            ║
║  │ • distribution_ids                      │   │ • origin_access_control_ids             │                            ║
║  │ • distribution_arns                     │   └─────────────────────────────────────────┘                            ║
║  │ • distribution_domain_names             │                                                                          ║
║  │ • distribution_hosted_zone_ids          │   ┌─────────────────────────────────────────┐                            ║
║  │ • distribution_statuses                 │   │           LOGGING                       │                            ║
║  │ • distribution_etags                    │   ├─────────────────────────────────────────┤                            ║
║  └─────────────────────────────────────────┘   │ • logging_bucket_id                     │                            ║
║                                                │ • logging_bucket_arn                    │                            ║
║                                                │ • logging_bucket_domain_name            │                            ║
║                                                └─────────────────────────────────────────┘                            ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
```

### Resource Summary

| Resource | Count Logic | Purpose |
|----------|-------------|---------|
| `aws_cloudfront_distribution` | 1 per entry in `var.distributions` | CloudFront distribution per domain group |
| `aws_cloudfront_monitoring_subscription` | 0 or 1 per distribution | CloudFront additional metrics subscription when enabled |
| `aws_cloudfront_origin_access_control` | 0 to N | OAC per S3 origin (shared across distributions) |
| `aws_cloudwatch_log_group` (access logs) | 0 or 1 | CloudWatch access-log group in us-east-1 (if CloudWatch logging active) |
| `aws_cloudwatch_log_delivery_source` | 0 or 1 per distribution | Standard logging v2 delivery source (if CloudWatch logging active) |
| `aws_cloudwatch_log_delivery_destination` | 0 or 1 | Standard logging v2 delivery destination, JSON output (if CloudWatch logging active) |
| `aws_cloudwatch_log_delivery` | 0 or 1 per distribution | Connects each delivery source to the destination (if CloudWatch logging active) |
| `aws_s3_bucket` (logging) | 0 or 1 | Access logs bucket (if S3 logging active and `logging_bucket_creation_enabled = true`) |
| `aws_s3_bucket_ownership_controls` | 0 or 1 | Logging bucket ownership (if logging bucket created) |
| `aws_s3_bucket_acl` | 0 or 1 | Logging bucket ACL (if logging bucket created) |
| `aws_s3_bucket_lifecycle_configuration` | 0 or 1 | Log retention (if logging bucket created) |

## Security Considerations

- **TLS 1.2 Minimum**: Default `minimum_protocol_version` is `TLSv1.2_2021`, enforcing modern TLS for all viewer connections.
- **Origin Access Control**: S3 origins use OAC (not legacy OAI) to securely sign requests with SigV4. You must also configure S3 bucket policies to allow the CloudFront distribution principal.
- **HTTPS by Default**: HTTP/2 and HTTP/3 are enabled by default. Use `redirect-to-https` viewer protocol policy to enforce HTTPS.
- **WAF Integration**: Associate a WAFv2 Web ACL (global scope) for DDoS protection, rate limiting, and request filtering at the edge.
- **No Public S3 Access**: When using OAC, S3 buckets should not have public access enabled. CloudFront signs requests on behalf of viewers.
- **Certificate Validation**: ACM certificate ARNs are validated to ensure they are in the correct format. ACM certificates for CloudFront must be in `us-east-1`.

## Notes

- **Modern Cache Policies Only**: This module uses cache policies and origin request policies instead of legacy `forwarded_values`. Reference AWS managed policies by ID or create custom policies outside this module.
- **OAC Only (No OAI)**: Only Origin Access Control is supported. OAI is legacy and does not work with S3 bucket policies using KMS encryption or S3 Object Lambda.
- **Multi-Distribution**: All distributions share the same origins, cache behaviors, and settings. Each distribution gets its own aliases, ACM certificate, and logging prefix. Use this for serving the same content under different domain groups.
- **Additional Metrics Cost**: CloudFront additional metrics are all-or-nothing per distribution. Enabling them turns on all 8 metrics and incurs a fixed CloudWatch per-metric monthly charge per distribution, independent of traffic volume.
- **Logging Prefixes**: When logging is enabled, each distribution logs under `<logging_prefix><distribution_key>/` to keep logs separated.
- **Route53 Records**: Create Route53 alias records externally using the `distribution_domain_names` and `distribution_hosted_zone_ids` outputs.
- **ACM Certificates**: CloudFront requires ACM certificates in `us-east-1` regardless of where other resources are deployed. Provision certificates externally and pass the ARN.
- **Price Classes**: `PriceClass_100` (US, Canada, Europe) is the default. Use `PriceClass_200` to add Asia/Middle East/Africa, or `PriceClass_All` for all edge locations.
- **S3 Bucket Policy**: After creating the distribution, update the S3 bucket policy to allow `s3:GetObject` from the CloudFront distribution. Use the `distribution_arns` output to construct the policy.
