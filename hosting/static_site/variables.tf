################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name prefix for all resources created by this module. Also used as the hosting bucket name (must be globally unique and a valid S3 bucket name)."

  validation {
    condition     = length(var.name) >= 3 && length(var.name) <= 63
    error_message = "The name must be between 3 and 63 characters."
  }

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.name))
    error_message = "The name must be a valid S3 bucket name: lowercase letters, numbers, hyphens, periods; must start and end with a letter or number."
  }
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to all resources."
  default     = {}
}

variable "routing" {
  type        = string
  description = "URI rewriting style applied at the edge before the version prefix is added. 'spa' rewrites every non-asset path to /<version>/index.html so a client-side router takes over. 'filesystem' rewrites /foo and /foo/ to /<version>/foo/index.html and serves /foo.js etc. as-is. Both styles are versioned identically."
  default     = "spa"

  validation {
    condition     = contains(["spa", "filesystem"], var.routing)
    error_message = "The routing must be 'spa' or 'filesystem'."
  }
}

variable "default_version" {
  type        = string
  description = "Version prefix used when KVS has neither a host-specific entry nor an 'active' key. Also used as the seed value for the 'active' KVS key on first apply. Pick a stable name like 'main' so the first deploy can sync to s3://<bucket>/<default_version>/ without further setup."
  default     = "main"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.default_version))
    error_message = "The default_version must contain only letters, numbers, '.', '_', '-'. Multi-segment versions (containing '/') are not supported: the cache-control function strips exactly one leading path segment to recover the viewer-facing path."
  }
}

################################################################################
# Distributions
################################################################################

variable "distributions" {
  type = map(object({
    aliases             = optional(list(string), [])
    acm_certificate_arn = optional(string)
    comment             = optional(string)
    enabled             = optional(bool, true)
  }))
  description = "A map of CloudFront distributions to create. Each entry shares the same S3 origin and cache behaviors but has its own aliases and ACM certificate. Defaults to a single 'main' distribution with no aliases (CloudFront default certificate)."
  default = {
    main = {}
  }

  validation {
    condition     = length(var.distributions) > 0
    error_message = "At least one distribution must be specified."
  }
}

variable "price_class" {
  type        = string
  description = "CloudFront price class. 'PriceClass_100' (US/Canada/Europe) is the cheapest; 'PriceClass_All' covers every edge location."
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "The price_class must be 'PriceClass_100', 'PriceClass_200', or 'PriceClass_All'."
  }
}

variable "minimum_protocol_version" {
  type        = string
  description = "Minimum TLS version for viewer connections (only applies when an ACM certificate is set on the distribution)."
  default     = "TLSv1.2_2021"
}

variable "geo_restriction_type" {
  type        = string
  description = "Geo restriction type: 'none', 'whitelist', or 'blacklist'."
  default     = "none"

  validation {
    condition     = contains(["none", "whitelist", "blacklist"], var.geo_restriction_type)
    error_message = "The geo_restriction_type must be 'none', 'whitelist', or 'blacklist'."
  }
}

variable "geo_restriction_locations" {
  type        = list(string)
  description = "ISO 3166-1-alpha-2 country codes for geo restriction."
  default     = []
}

variable "web_acl_id" {
  type        = string
  description = "ARN of a global-scope WAFv2 Web ACL to associate with all distributions."
  default     = null

  validation {
    condition     = var.web_acl_id == null || can(regex("^arn:aws:wafv2:", var.web_acl_id))
    error_message = "The web_acl_id must be a valid WAFv2 Web ACL ARN."
  }
}

variable "deployment_wait_enabled" {
  type        = bool
  description = "Whether to wait for each distribution to be deployed before completing apply."
  default     = true
}

################################################################################
# Hosting Bucket
################################################################################

variable "bucket_versioning_enabled" {
  type        = bool
  description = "Enable versioning on the hosting bucket. Disable only if you know what you're doing — this is independent of the per-deploy version prefix and protects against accidental overwrites."
  default     = true
}

variable "bucket_force_destroy_enabled" {
  type        = bool
  description = "Allow `tofu destroy` to delete the hosting bucket even if it is not empty. Useful for ephemeral environments; dangerous in production."
  default     = false
}

variable "bucket_lifecycle_rules" {
  type = list(object({
    id      = string
    enabled = optional(bool, true)
    prefix  = optional(string)
    tags    = optional(map(string))
    expiration = optional(object({
      days                         = optional(number)
      date                         = optional(string)
      expired_object_delete_marker = optional(bool)
    }))
    noncurrent_version_expiration = optional(object({
      noncurrent_days           = optional(number)
      newer_noncurrent_versions = optional(number)
    }))
    transitions = optional(list(object({
      days          = optional(number)
      date          = optional(string)
      storage_class = string
    })), [])
    noncurrent_version_transitions = optional(list(object({
      noncurrent_days           = optional(number)
      newer_noncurrent_versions = optional(number)
      storage_class             = string
    })), [])
    abort_incomplete_multipart_upload_days = optional(number)
  }))
  description = "Lifecycle rules for the hosting bucket. Defaults to expiring noncurrent versions after 30 days and aborting incomplete multipart uploads after 7 days; pass an empty list to disable defaults."
  default = [
    {
      id = "expire-noncurrent-versions"
      noncurrent_version_expiration = {
        noncurrent_days = 30
      }
      abort_incomplete_multipart_upload_days = 7
    }
  ]
}

variable "kms_key_arn" {
  type        = string
  description = "Optional KMS key ARN for SSE-KMS encryption of the hosting bucket. If null, SSE-S3 (AES256) is used."
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws:kms:", var.kms_key_arn))
    error_message = "The kms_key_arn must be null or a valid KMS key ARN."
  }
}

################################################################################
# Origin
################################################################################

variable "origin_shield_enabled" {
  type        = bool
  description = "Enable CloudFront Origin Shield in front of the hosting bucket. Reduces origin load and improves cache hit ratio for high-traffic sites. The Origin Shield region is derived automatically from the bucket region: same region when CloudFront offers Origin Shield there, otherwise the nearest supported region per the AWS mapping table. Set origin_shield_region to override."
  default     = false
}

variable "origin_shield_region" {
  type        = string
  description = "Override the automatically derived Origin Shield region. Only used when origin_shield_enabled is true. Leave null to derive from the bucket region."
  default     = null
}

variable "additional_origin_headers" {
  type = list(object({
    name  = string
    value = string
  }))
  description = "Extra custom headers to send to the S3 origin."
  default     = []
}

################################################################################
# Cache Behavior
################################################################################

variable "cache_policy_id" {
  type        = string
  description = "CloudFront cache policy ID for the default behavior. When null (the default), the module creates a cache policy identical to AWS-managed CachingOptimized but with a 1-year default TTL — safe because versioned deploys change the cache key on every promotion, and S3 objects carry no Cache-Control of their own. Set to a policy ID (e.g. CachingOptimized 658327ea-f89d-4fab-a63d-7e88639e58f6) to use your own."
  default     = null
}

variable "origin_request_policy_id" {
  type        = string
  description = "CloudFront origin request policy ID. Defaults to AWS-managed CORS-S3Origin (forwards Origin/Access-Control-* headers, no cookies/query strings)."
  default     = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"
}

variable "response_headers_presets" {
  type        = list(string)
  description = <<-EOT
    AWS-managed response-header sets to attach when neither `response_headers_policy_id` nor `response_headers_policy` is set. CloudFront allows exactly one response-headers policy per cache behavior, so the selection maps onto the single AWS-managed policy that covers the combination:

      - "security_headers": HSTS, X-Content-Type-Options nosniff, X-Frame-Options SAMEORIGIN, Referrer-Policy strict-origin-when-cross-origin, X-XSS-Protection. Remove it if the site must be embeddable in cross-origin iframes (SAMEORIGIN blocks that).
      - "cors": Access-Control-Allow-Origin: * for simple CORS requests (SimpleCORS).
      - "cors_preflight": CORS from any origin including OPTIONS preflight (Allow-Methods/Expose-Headers). Supersedes "cors" when both are selected.

    Pass an empty list to attach no response-headers policy.
  EOT
  default     = ["security_headers"]
  nullable    = false

  validation {
    condition     = alltrue([for p in var.response_headers_presets : contains(["security_headers", "cors", "cors_preflight"], p)])
    error_message = "The response_headers_presets entries must be 'security_headers', 'cors', or 'cors_preflight'."
  }
}

variable "response_headers_policy_id" {
  type        = string
  description = "ID of an externally-managed CloudFront response-headers policy to attach to the default behavior. Use when you have a centrally-managed policy (e.g. an org-wide CSP) you want to share across distributions. Takes precedence over `response_headers_policy` and the `response_headers_presets` default. Note: do NOT put `Cache-Control` in this policy with override=true; it will fight the cache-control function."
  default     = null
}

variable "response_headers_policy" {
  type = object({
    security_headers_config = optional(object({
      strict_transport_security = optional(object({
        access_control_max_age_sec = number
        include_subdomains         = optional(bool, true)
        preload                    = optional(bool, false)
        override                   = optional(bool, true)
      }))
      content_security_policy = optional(object({
        content_security_policy = string
        override                = optional(bool, true)
      }))
      content_type_options = optional(object({
        override = optional(bool, true)
      }))
      frame_options = optional(object({
        frame_option = string
        override     = optional(bool, true)
      }))
      referrer_policy = optional(object({
        referrer_policy = string
        override        = optional(bool, true)
      }))
      xss_protection = optional(object({
        protection = bool
        mode_block = optional(bool, true)
        report_uri = optional(string)
        override   = optional(bool, true)
      }))
    }))

    cors_config = optional(object({
      access_control_allow_credentials = bool
      access_control_allow_headers     = list(string)
      access_control_allow_methods     = list(string)
      access_control_allow_origins     = list(string)
      access_control_expose_headers    = optional(list(string), [])
      access_control_max_age_sec       = optional(number, 600)
      origin_override                  = optional(bool, false)
    }))

    custom_headers = optional(list(object({
      header   = string
      value    = string
      override = optional(bool, true)
    })), [])

    remove_headers = optional(list(string), [])
  })
  description = <<-EOT
    Declarative configuration for a module-managed CloudFront response-headers policy. Use this for security headers (HSTS, CSP, X-Frame-Options, Referrer-Policy, X-Content-Type-Options nosniff), CORS, arbitrary custom response headers, and stripped headers. Mirrors the AWS `aws_cloudfront_response_headers_policy` resource shape — see the module README for examples.

    Coexists with the cache-control function: the function writes Cache-Control on every response in viewer-response, then the response-headers policy applies. Don't put Cache-Control in `custom_headers` with override=true unless you intentionally want to overwrite what the function set.

    Precedence on the default behavior: caller-supplied `response_headers_policy_id` > this module-managed policy > AWS-managed policy selected by `response_headers_presets`. Set to null (default) to fall through to the presets default.
  EOT
  default     = null

  validation {
    condition = var.response_headers_policy == null ? true : (
      try(var.response_headers_policy.security_headers_config.frame_options, null) == null ||
      contains(["DENY", "SAMEORIGIN"], try(var.response_headers_policy.security_headers_config.frame_options.frame_option, ""))
    )
    error_message = "frame_options.frame_option must be either 'DENY' or 'SAMEORIGIN'."
  }
}

variable "error_document" {
  type        = string
  description = <<-EOT
    Bucket key (without leading slash) of the custom error page served with a 404 status when a requested object does not exist, e.g. '404.html'. Set to an empty string to disable and serve plain 404 responses (passing null applies the default instead — null means "use default" in Terraform).

    CloudFront fetches this page directly from the origin without running the viewer-request rewrite function, so the key is resolved at the BUCKET ROOT, outside version prefixes. To source it from build assets, emit '404.html' at the root of the build output (the default convention in Astro, Hugo, Eleventy, SvelteKit, etc.) and have the deploy copy '<version>/404.html' to '/404.html' at promotion time:

      aws s3 cp s3://<bucket>/<version>/404.html s3://<bucket>/404.html

    If the key does not exist, viewers still receive a correct 404 status (missing objects return real 404s because the bucket policy grants CloudFront s3:ListBucket), just without the custom body.
  EOT
  default     = "404.html"
  nullable    = false

  validation {
    condition     = var.error_document == "" || can(regex("^[^/]", var.error_document))
    error_message = "The error_document must be a bucket key without a leading slash (e.g. '404.html'), or an empty string to disable."
  }
}

variable "error_caching_min_ttl" {
  type        = number
  description = "Seconds CloudFront caches 404 error responses at the edge before re-checking the origin. Applies whether or not error_document is set. Defaults to 1 day: versioned deploys make cached 404s safe because every promotion produces fresh cache keys. Lower this if you overwrite files inside already-promoted S3 directories and need missing-then-uploaded files to appear quickly."
  default     = 86400

  validation {
    condition     = var.error_caching_min_ttl >= 0 && var.error_caching_min_ttl <= 31536000
    error_message = "The error_caching_min_ttl must be between 0 and 31536000 seconds."
  }
}

variable "no_cache_paths" {
  type        = list(string)
  description = "Path patterns that should bypass CloudFront caching. Empty by default — versioned deploys make every promotion a fresh cache key, so per-path cache busting is rarely needed."
  default     = []
}

variable "default_root_object" {
  type        = string
  description = "Object name resolved when a viewer requests '/'. Defaults to 'index.html'."
  default     = "index.html"
}

################################################################################
# Cache-Control (viewer-response CloudFront Function)
#
# A viewer-response function classifies every response by the rewritten URI
# shape and writes Cache-Control accordingly:
#
#   - URI in html_path_overrides (service workers, PWA manifests, SEO files),
#     or contains a dotted segment, or has no extension, or ends in
#     .html / .htm  ->  html_cache_control
#   - any other extension                                  ->  assets_cache_control
#
# This sidesteps the cache-behavior matching pitfall that bit ENG-4785: the
# behavior-level response_headers_policy_id can only see the original viewer
# URI (pre-rewrite), but a viewer-response function sees the rewritten URI
# where HTML vs asset is unambiguous from the file extension.
################################################################################

variable "cache_control_enabled" {
  type        = bool
  description = "Whether the module attaches a viewer-response CloudFront Function that writes Cache-Control on every response. Disable to delegate Cache-Control to S3 object metadata or to a caller-supplied response_headers_policy_id."
  default     = true
}

variable "html_cache_control" {
  type        = string
  description = "Cache-Control header value emitted by the cache-control function for HTML responses (URI has no extension, ends in .html/.htm, contains a dotted segment, or matches html_path_overrides). Because this header is written in viewer-response, CloudFront never uses it for edge TTLs — edge freshness comes from the versioned cache key, which changes on every promotion. The only real consumer is the browser (and any intercepting proxy), so the default forces revalidation on every navigation: the browser stores the HTML, sends a conditional GET, and the CloudFront edge answers 304 from cache. Fresh HTML on the first navigation after a version flip, at the cost of one cheap conditional request."
  default     = "public, max-age=0, must-revalidate"
}

variable "assets_cache_control" {
  type        = string
  description = "Cache-Control header value emitted by the cache-control function for asset responses (URI has any non-html file extension and is not in html_path_overrides). Defaults to a one-year immutable browser cache, which is safe because every asset URL is pinned to /<version>/... by the rewriter so bytes never collide between deploys."
  default     = "public, max-age=31536000, immutable"
}

variable "html_path_overrides" {
  type        = list(string)
  description = "Exact-match viewer URIs that always receive html_cache_control regardless of file extension. Defaults cover the common service-worker, PWA, and SEO files where stable, non-hashed URLs MUST NOT be cached as immutable — a wedged service worker can brick a site until the user clears site data. Pass an empty list to opt out of the defaults; extend it for project-specific files."
  default = [
    "/service-worker.js",
    "/sw.js",
    "/manifest.json",
    "/manifest.webmanifest",
    "/favicon.ico",
    "/robots.txt",
    "/sitemap.xml",
  ]
}

################################################################################
# CloudFront KeyValueStore (always created)
################################################################################

variable "kvs_initial_data" {
  type        = map(string)
  description = "Optional seed entries for the KeyValueStore. Use `host -> version` to pin specific aliases (e.g. {\"staging.example.com\" = \"v_staging\"}) or `\"active\" -> version` to override the default_version seed. Version values must be single path segments (no '/') — the cache-control function strips exactly one leading segment to recover the viewer-facing path. Subsequent edits should happen via `aws cloudfront-keyvaluestore put-key` from CI to avoid Terraform churn for ephemeral previews."
  default     = {}

  validation {
    condition     = alltrue([for k, v in var.kvs_initial_data : can(regex("^[A-Za-z0-9._-]+$", v))])
    error_message = "The kvs_initial_data version values must contain only letters, numbers, '.', '_', '-' (single path segment, no '/')."
  }
}

################################################################################
# Logging
################################################################################

variable "logging_enabled" {
  type        = bool
  description = "Enable CloudFront access logging. Defaults to true with CloudWatch Logs delivery; see logging_destination."
  default     = true
}

variable "logging_destination" {
  type        = string
  description = "Where CloudFront delivers access logs when logging_enabled is true. 'cloudwatch' uses CloudFront standard logging v2 into a module-managed CloudWatch Logs group (viewable in the Ravion UI; ingestion costs more at very high traffic). 's3' uses legacy standard logging into an S3 bucket (cheapest for high traffic)."
  default     = "cloudwatch"

  validation {
    condition     = contains(["cloudwatch", "s3"], var.logging_destination)
    error_message = "The logging_destination must be 'cloudwatch' or 's3'."
  }
}

variable "logging_bucket_creation_enabled" {
  type        = bool
  description = "Whether to create a new S3 bucket for CloudFront access logs. Only applies when logging_enabled is true and logging_destination is 's3'."
  default     = false
}

variable "logging_bucket_domain_name" {
  type        = string
  description = "Domain name of an existing S3 bucket for access logs (e.g. 'mybucket.s3.amazonaws.com'). Used when logging_enabled is true, logging_destination is 's3', and logging_bucket_creation_enabled is false."
  default     = null
}

variable "logging_prefix" {
  type        = string
  description = "Base S3 key prefix for access logs. Each distribution logs under '<logging_prefix><distribution_key>/'. Only applies when logging_destination is 's3'."
  default     = ""
}

variable "logging_retention_days" {
  type        = number
  description = "Days to retain CloudFront access logs — the CloudWatch log group retention when logging_destination is 'cloudwatch', or the S3 lifecycle expiry when logging_destination is 's3' with a module-created bucket."
  default     = 365

  validation {
    condition     = var.logging_destination != "cloudwatch" || contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.logging_retention_days)
    error_message = "When logging_destination is 'cloudwatch', logging_retention_days must be a valid CloudWatch Logs retention value (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, or 3653)."
  }
}

################################################################################
# Deploy Role (optional)
################################################################################

variable "deploy_role_creation_enabled" {
  type        = bool
  description = "Whether to create an IAM role that CI can assume to upload to the hosting bucket and flip the active version in KVS."
  default     = false
}

variable "deploy_role_trust_policy" {
  type        = string
  description = "Trust policy JSON for the deploy role. Required when deploy_role_creation_enabled = true. Typically grants sts:AssumeRoleWithWebIdentity to a GitHub OIDC provider or sts:AssumeRole to a CI account."
  default     = null

  validation {
    condition     = var.deploy_role_trust_policy == null || can(jsondecode(var.deploy_role_trust_policy))
    error_message = "The deploy_role_trust_policy must be valid JSON."
  }
}

variable "deploy_role_name" {
  type        = string
  description = "Override name for the deploy role. Defaults to '<name>-deploy'."
  default     = null
}

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
}
