locals {
  region = coalesce(var.region, data.aws_region.current.region)

  # Origin Shield region derivation. CloudFront offers Origin Shield only in
  # regions with a regional edge cache; for buckets in those regions the
  # shield lives in the same region, otherwise in the nearest supported
  # region per the AWS mapping table (entries past the documented eight are
  # this module's nearest-region picks for newer regions):
  # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/origin-shield.html
  origin_shield_supported_regions = [
    "us-east-1", "us-east-2", "us-west-2",
    "ap-south-1", "ap-northeast-1", "ap-northeast-2",
    "ap-southeast-1", "ap-southeast-2",
    "eu-central-1", "eu-west-1", "eu-west-2",
    "sa-east-1", "me-central-1",
  ]

  origin_shield_nearest_region = {
    # AWS-documented mappings
    "us-west-1"    = "us-west-2"
    "af-south-1"   = "eu-west-1"
    "ap-east-1"    = "ap-southeast-1"
    "ca-central-1" = "us-east-1"
    "eu-south-1"   = "eu-central-1"
    "eu-west-3"    = "eu-west-2"
    "eu-north-1"   = "eu-west-2"
    "me-south-1"   = "ap-south-1"
    # Nearest supported region for newer regions not covered by the AWS table
    "ap-east-2"      = "ap-northeast-1"
    "ap-northeast-3" = "ap-northeast-1"
    "ap-south-2"     = "ap-south-1"
    "ap-southeast-3" = "ap-southeast-1"
    "ap-southeast-4" = "ap-southeast-2"
    "ap-southeast-5" = "ap-southeast-1"
    "ap-southeast-7" = "ap-southeast-1"
    "ca-west-1"      = "us-west-2"
    "eu-central-2"   = "eu-central-1"
    "eu-south-2"     = "eu-west-2"
    "il-central-1"   = "me-central-1"
    "mx-central-1"   = "us-east-1"
  }

  origin_shield_region = coalesce(
    var.origin_shield_region,
    contains(local.origin_shield_supported_regions, local.region)
    ? local.region
    : lookup(local.origin_shield_nearest_region, local.region, "us-east-1"),
  )
}

locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "hosting/static_site"
  }
  tags = merge(local.default_tags, var.tags)

  origin_id = "s3-hosting"

  # "main" is the conventional primary distribution; fall back to the lexically
  # first key so primary_domain works for any distributions map.
  primary_distribution_key = contains(keys(var.distributions), "main") ? "main" : sort(keys(var.distributions))[0]

  # The CF Function reads `active` from KVS unless callers seed it themselves.
  active_kvs_seed = merge(
    { active = var.default_version },
    var.kvs_initial_data,
  )

  # viewer-request runs first (URI rewrite to /<version>/...), viewer-response
  # runs last (Cache-Control header from rewritten URI shape). Both are
  # attached to every behavior — no_cache_paths included — so the
  # Cache-Control values stay consistent regardless of which behavior matched.
  cff_associations = concat(
    [{
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.rewrite.arn
    }],
    var.cache_control_enabled ? [{
      event_type   = "viewer-response"
      function_arn = aws_cloudfront_function.cache_control[0].arn
    }] : [],
  )

  managed_cache_disabled_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"

  # Caller-supplied cache_policy_id wins over the module-managed 1-year policy.
  effective_cache_policy_id = var.cache_policy_id != null ? var.cache_policy_id : aws_cloudfront_cache_policy.this[0].id

  # response_headers_presets -> AWS-managed response-headers policy ID.
  # CloudFront allows exactly one response-headers policy per behavior, so the
  # preset combination selects the single managed policy that covers it. IDs
  # from https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-response-headers-policies.html
  # cors_preflight implies cors (the preflight policies are supersets of
  # SimpleCORS), so selecting it with or without "cors" behaves identically.
  presets_security  = contains(var.response_headers_presets, "security_headers")
  presets_preflight = contains(var.response_headers_presets, "cors_preflight")
  presets_cors      = contains(var.response_headers_presets, "cors") || local.presets_preflight

  managed_response_headers_policy_id = (
    local.presets_preflight && local.presets_security ? "eaab4381-ed33-4a86-88ca-d9558dc6cd63" : # CORS-with-preflight-and-SecurityHeadersPolicy
    local.presets_preflight ? "5cc3b908-e619-4b99-88e5-2cf7f45965bd" :                           # CORS-With-Preflight
    local.presets_cors && local.presets_security ? "e61eb60c-9c35-4d20-a928-2b84e02af89c" :      # CORS-and-SecurityHeadersPolicy
    local.presets_cors ? "60669652-455b-4ae9-85a4-c4c02393f86c" :                                # SimpleCORS
    local.presets_security ? "67f7725c-6f97-4210-82d7-5512b31e9d03" :                            # SecurityHeadersPolicy
    null
  )

  # Precedence: caller-supplied response_headers_policy_id > module-managed
  # policy from var.response_headers_policy > AWS-managed policy selected by
  # response_headers_presets (security headers by default). The cache-control
  # function always runs regardless — it's a separate viewer-response
  # association.
  module_response_headers_policy_id = try(aws_cloudfront_response_headers_policy.this[0].id, null)
  effective_response_headers_policy_id = try(coalesce(
    var.response_headers_policy_id,
    local.module_response_headers_policy_id,
    local.managed_response_headers_policy_id,
  ), null)

  # Missing objects return real 404s (the bucket policy grants CloudFront
  # s3:ListBucket, so S3 distinguishes NoSuchKey from AccessDenied). When
  # error_document is set, serve it as the 404 body while keeping the 404
  # status. The error-page fetch bypasses the viewer-request rewrite, so the
  # key resolves at the bucket root — deploys copy <version>/404.html there
  # at promotion time. A genuine 403 now only means "blocked" (e.g. WAF),
  # never "file missing", so it is deliberately not mapped.
  # The 404 custom error response is always emitted so error_caching_min_ttl
  # always applies; the response page is only attached when error_document is
  # set.
  #
  # Custom error responses are distribution-wide: CloudFront cannot scope them
  # to a cache behavior. With origin_routes set, a 404 from the API would get
  # the static 404.html body and be cached for a day, shared by every viewer
  # (CachingDisabled does not stop error caching). So routed distributions
  # drop the error page and pin error caching to 0 for every cacheable code.
  origin_routes_enabled = length(var.origin_routes) > 0
  error_document        = local.origin_routes_enabled ? "" : var.error_document

  custom_error_responses = local.origin_routes_enabled ? [
    for code in [400, 403, 404, 405, 414, 416, 500, 501, 502, 503, 504] : {
      error_code            = code
      response_code         = null
      response_page_path    = null
      error_caching_min_ttl = 0
    }
    ] : [
    {
      error_code            = 404
      response_code         = var.error_document == "" ? null : 404
      response_page_path    = var.error_document == "" ? null : "/${var.error_document}"
      error_caching_min_ttl = var.error_caching_min_ttl
    }
  ]

  # One custom origin per route; one behavior per path pattern. No CloudFront
  # Functions: the version rewrite would send /v1/... to /<version>/index.html
  # and the Cache-Control writer would stamp HTML/asset headers onto API
  # responses.
  origin_route_origins = [
    for i, r in var.origin_routes : {
      origin_id                = "route-${i}"
      domain_name              = r.domain_name
      origin_path              = r.origin_path
      origin_protocol_policy   = r.origin_protocol_policy
      http_port                = r.http_port
      https_port               = r.https_port
      origin_read_timeout      = r.origin_read_timeout
      origin_keepalive_timeout = r.origin_keepalive_timeout
      connection_timeout       = r.connection_timeout
      connection_attempts      = r.connection_attempts
      custom_headers           = r.custom_headers
    }
  ]

  origin_route_behaviors = flatten([
    for i, r in var.origin_routes : [
      for path in r.path_patterns : {
        path_pattern                 = path
        target_origin_id             = "route-${i}"
        viewer_protocol_policy       = "redirect-to-https"
        allowed_methods              = r.allowed_methods
        cached_methods               = ["GET", "HEAD"]
        compression_enabled          = true
        cache_policy_id              = r.cache_policy_id
        origin_request_policy_id     = r.origin_request_policy_id
        response_headers_policy_id   = r.response_headers_policy_id
        function_associations        = []
        lambda_function_associations = []
        realtime_log_config_arn      = null
      }
    ]
  ])

  no_cache_behaviors = [
    for path in var.no_cache_paths : {
      path_pattern                 = path
      target_origin_id             = local.origin_id
      viewer_protocol_policy       = "redirect-to-https"
      allowed_methods              = ["GET", "HEAD", "OPTIONS"]
      cached_methods               = ["GET", "HEAD"]
      compression_enabled          = true
      cache_policy_id              = local.managed_cache_disabled_id
      origin_request_policy_id     = var.origin_request_policy_id
      response_headers_policy_id   = local.effective_response_headers_policy_id
      function_associations        = local.cff_associations
      lambda_function_associations = []
      realtime_log_config_arn      = null
    }
  ]

  # The custom error page lives at a stable, unversioned bucket-root key, so
  # it must NOT inherit the default behavior's 1-year edge TTL — a changed
  # 404 page would serve stale until invalidated. A dedicated behavior pins
  # it to the managed CachingDisabled policy; the error *responses* viewers
  # receive are still cached per error_caching_min_ttl, so S3 sees at most
  # one error-page fetch per edge location per that window.
  error_document_behaviors = local.error_document == "" ? [] : [
    {
      path_pattern                 = "/${local.error_document}"
      target_origin_id             = local.origin_id
      viewer_protocol_policy       = "redirect-to-https"
      allowed_methods              = ["GET", "HEAD", "OPTIONS"]
      cached_methods               = ["GET", "HEAD"]
      compression_enabled          = true
      cache_policy_id              = local.managed_cache_disabled_id
      origin_request_policy_id     = var.origin_request_policy_id
      response_headers_policy_id   = local.effective_response_headers_policy_id
      function_associations        = local.cff_associations
      lambda_function_associations = []
      realtime_log_config_arn      = null
    }
  ]

  # Origin routes go first so an explicit backend route wins over overlapping
  # no-cache patterns.
  ordered_behaviors = concat(local.origin_route_behaviors, local.no_cache_behaviors, local.error_document_behaviors)

  cff_request_rewrite_name = format(
    "%s-%s-request-rewrite",
    substr(replace(var.name, "/[^a-zA-Z0-9-_]/", "-"), 0, 39),
    substr(sha1(var.name), 0, 8),
  )
  cff_cache_control_name       = substr(replace("${var.name}-cache-ctl", "/[^a-zA-Z0-9-_]/", "-"), 0, 64)
  cache_policy_name            = substr(replace("${var.name}-cache", "/[^a-zA-Z0-9-_]/", "-"), 0, 64)
  response_headers_policy_name = substr(replace("${var.name}-rh", "/[^a-zA-Z0-9-_]/", "-"), 0, 64)
  kvs_name                     = substr(replace("${var.name}-kvs", "/[^a-zA-Z0-9-]/", "-"), 0, 64)
  deploy_role_name             = var.deploy_role_name != null ? var.deploy_role_name : "${var.name}-deploy"
  oac_policy_sid               = "AllowCloudFrontServicePrincipal"
  partition                    = data.aws_partition.current.partition
  hosting_bucket_arn           = "arn:${local.partition}:s3:::${var.name}"
}
