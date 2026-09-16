# Static Site Hosting

End-to-end composite module for hosting static sites on AWS using S3 + CloudFront. Composes [`storage/s3`](../../storage/s3) and [`cdn/cloudfront`](../../cdn/cloudfront).

Every deployment is **versioned**. A CloudFront KeyValueStore holds a `host -> version` map; a single CloudFront Function rewrites every viewer request to `/<version>/...` before the cache lookup. Promoting or rolling back a build is one `put-key` call against the KVS.

## Features

- **Versioned-by-default**: every deploy lands at `s3://<bucket>/<version>/`, the KVS `active` key points at the live one.
- **Instant rollback**: flip `active` (or any per-host KVS entry) — KVS reads at the edge propagate within seconds.
- **No CloudFront invalidations needed**: the rewriter changes the rewritten URI, which is part of the cache key, so each promotion is automatically a fresh cache key.
- **Two routing styles**: `spa` (every non-asset path serves `<version>/index.html` for client-side routers) and `filesystem` (clean URLs, `/foo` → `<version>/foo/index.html`).
- **Per-host overrides**: pin staging to a specific version, run PR previews on `pr-*.preview.example.com` subdomains, gradual cutovers — all via KVS keys.
- **Origin Access Control (OAC)** by default — no public buckets, no legacy OAI.
- **Multiple distributions** sharing one origin (e.g., a production domain group + staging domain group).
- **HTTP/2 + HTTP/3** by default.
- **Optional WAFv2** integration.
- **Access logging on by default** — CloudWatch Logs delivery (standard logging v2, via cdn/cloudfront), with legacy S3 delivery available for cost-sensitive high-traffic sites.
- **Optional CI deploy role** with least-privilege `s3:Put*` + KVS `PutKey`/`DeleteKey` + `cloudfront:CreateInvalidation`.
- **Origin Shield** support.
- **SSE-KMS** support on the hosting bucket.

## Architecture

```
                +----------+
                |  Viewer  |
                +----+-----+
                     | HTTPS
                     v
         +-----------+------------+
         |  CloudFront            |
         |   - HTTP/2 + HTTP/3    |
         |   - WAF (optional)     |
         |   - Logging (optional) |
         +-----------+------------+
                     | viewer-request
                     v
         +-----------+------------+        +-----+
         | rewriter (CFF)         |<------>| KVS |
         |   1. host -> version   |        +-----+
         |   2. rewrite URI:      |
         |      /foo -> /<v>/...  |
         +-----------+------------+
                     | (rewritten URI = cache key)
                     v
         +-----------+------------+
         | S3 Hosting Bucket      |
         | (private, OAC SigV4)   |
         +-----------+------------+
                     | response
                     v
         +-----------+------------+
         | cache-control (CFF)    |
         |   viewer-response      |
         |   sets Cache-Control   |
         |   from rewritten URI   |
         +------------------------+
```

## Quick Start

### SPA (React/Vue/TanStack Router/etc.)

```hcl
module "site" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//hosting/static_site?ref=v1.0.0"

  name = "my-app"

  distributions = {
    main = {
      aliases             = ["app.example.com"]
      acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc-123"
    }
  }
}
```

The viewer-response function automatically classifies every response as HTML or asset by the rewritten URI extension — no `long_cache_paths`, no per-project asset directory list. Hashed assets like `/_astro/foo.abc123.js` or `/main.def456.css` get `immutable, max-age=1y`; SPA routes like `/dashboard`, root files like `/favicon.ico`, and `*.html` documents get `public, max-age=0, must-revalidate` so browsers pick up a promoted version on the very next navigation.

### Filesystem (Astro/Hugo/MkDocs)

```hcl
module "site" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//hosting/static_site?ref=v1.0.0"

  name    = "my-docs"
  routing = "filesystem"

  distributions = {
    main = {
      aliases             = ["docs.example.com"]
      acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc-123"
    }
  }
}
```

### With deploy role + per-host pinning

```hcl
module "site" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//hosting/static_site?ref=v1.0.0"

  name = "my-app"

  distributions = {
    main = {
      aliases             = ["app.example.com", "staging.example.com", "*.preview.example.com"]
      acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc-123"
    }
  }

  # Pin staging to a known-good version while prod tracks 'active'.
  kvs_initial_data = {
    "staging.example.com" = "v_staging"
  }

  deploy_role_creation_enabled = true
  deploy_role_trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com" }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        StringLike   = { "token.actions.githubusercontent.com:sub" = "repo:my-org/my-repo:*" }
      }
    }]
  })
}
```

## Deploy and rollback

A new build is two steps from CI: upload, then flip.

```bash
VERSION="v$(git rev-parse --short HEAD)"

# 1. Upload the build to its own prefix (idempotent — re-runnable, no live impact)
aws s3 sync ./dist s3://${HOSTING_BUCKET}/${VERSION}/ --delete

# 2. Promote: point 'active' at the new version
KVS_ARN=$(tofu output -raw cloudfront_keyvaluestore_arn)
ETAG=$(aws cloudfront-keyvaluestore describe-key-value-store --kvs-arn $KVS_ARN --query ETag --output text)
aws cloudfront-keyvaluestore put-key \
  --kvs-arn $KVS_ARN --if-match $ETAG \
  --key active --value $VERSION

# 3. (optional) Publish the promoted version's 404 page to the bucket root —
#    the custom-error-page fetch bypasses the version rewrite (see "404 handling")
aws s3 cp s3://${HOSTING_BUCKET}/${VERSION}/404.html s3://${HOSTING_BUCKET}/404.html || true
```

Rollback is the same `put-key` call with the previous version. `outputs.set_active_version_command` returns the snippet pre-filled with the KVS ARN.

### PR previews

```bash
# Build for the PR's preview host
aws s3 sync ./dist s3://${HOSTING_BUCKET}/v_pr-42/ --delete

# Map the preview hostname to that version
ETAG=$(aws cloudfront-keyvaluestore describe-key-value-store --kvs-arn $KVS_ARN --query ETag --output text)
aws cloudfront-keyvaluestore put-key \
  --kvs-arn $KVS_ARN --if-match $ETAG \
  --key pr-42.preview.example.com --value v_pr-42

# Tear down on PR close
ETAG=$(aws cloudfront-keyvaluestore describe-key-value-store --kvs-arn $KVS_ARN --query ETag --output text)
aws cloudfront-keyvaluestore delete-key \
  --kvs-arn $KVS_ARN --if-match $ETAG \
  --key pr-42.preview.example.com
```

The deploy role created when `deploy_role_creation_enabled = true` has exactly the S3 + KVS permissions to do all of this.

## How the rewriter resolves a version

For each viewer request, the CloudFront Function does:

1. Look up `host` in the KVS → if hit, that version wins.
2. Look up `active` in the KVS → that's the production default.
3. Fall back to `default_version` (apply-time constant, defaults to `"main"`) → makes the very first deploy work before any KVS edits.

It then rewrites the URI by routing style:

| Routing | `/` | `/foo.js` | `/foo` or `/foo/` |
|---|---|---|---|
| `spa` | `/<v>/index.html` | `/<v>/foo.js` | `/<v>/index.html` |
| `filesystem` | `/<v>/index.html` | `/<v>/foo.js` | `/<v>/foo/index.html` |

Because CloudFront's cache key incorporates the rewritten URI, two different versions never collide in cache.

## Provider configuration

```hcl
provider "aws" {
  region = "us-west-2"
}
```

Only the default `aws` provider is required. ACM certificates for CloudFront aliases must still live in `us-east-1` regardless of the rest of your stack — provision them with [`security/acm_certificate`](../../security/acm_certificate) using a `us_east_1` provider alias in your root module and pass the ARN to `distributions[].acm_certificate_arn`.

## Cache strategy

Two CloudFront Functions split responsibilities cleanly:

| Function | Event | Job |
|---|---|---|
| rewriter | viewer-request | Looks up the active version in the KVS and prepends `/<version>/` to the URI so each promotion produces a fresh cache key. |
| cache-control | viewer-response | Writes `Cache-Control` on every response based on the rewritten URI shape. HTML responses revalidate on every navigation; hashed assets get the immutable 1-year browser cache. These headers steer the **browser only** — CloudFront never uses viewer-response headers for its own edge TTLs. |

**CDN-side cache policy** (defaults to a module-managed policy: 1-year default TTL, gzip+brotli, no headers/cookies/QS in the key — overridable via `cache_policy_id`):

| Path pattern | Cache policy | Why |
|---|---|---|
| (default) | module-managed (1y TTL) | The rewriter pins every URL to `/<version>/...`, so each response has a version-unique cache key — safe to cache at the edge for a year regardless of HTML vs asset. |
| `no_cache_paths` | AWS-managed `CachingDisabled` | Optional escape hatch — versioning makes per-path cache busting unnecessary in most cases. |

**Browser-side `Cache-Control`** (written by the viewer-response function when `cache_control_enabled = true`, the default):

| Rewritten URI shape | `Cache-Control` | Why |
|---|---|---|
| URI in `html_path_overrides` (`/service-worker.js`, `/sw.js`, `/manifest.json`, `/favicon.ico`, `/robots.txt`, `/sitemap.xml`, `/manifest.webmanifest`) | `public, max-age=0, must-revalidate` | Stable, non-hashed root files. Caching them as `immutable` is dangerous — a wedged service worker can brick a site until users clear site data. Override the list per-project with `html_path_overrides`. |
| Contains a dotted segment (e.g. `/.well-known/openid-configuration`) | `public, max-age=0, must-revalidate` | RFC 8615 well-known URIs and dot-prefixed config directories are served verbatim and are not content-hashed. |
| No file extension or ends in `.html` / `.htm` | `public, max-age=0, must-revalidate` | Catches SPA routes (`/dashboard`) after the rewriter sent them to `/<v>/index.html`, filesystem routes (`/about/`) sent to `/<v>/about/index.html`, and explicit `.html` requests. The browser stores the HTML but revalidates on every navigation — a conditional GET answered `304` by the CloudFront edge — so a version flip is visible on the first navigation after promotion. Edge freshness needs no header at all: the rewriter changes the cache key on every promotion. |
| Any other extension (`.js`, `.css`, `.png`, `.woff2`, …) | `public, max-age=31536000, immutable` | Every asset URL is pinned to `/<version>/...` by the rewriter, so the bytes at a given URL never change between deploys. Browsers can cache these for a year and skip even conditional revalidation. |

Tune the headers via `html_cache_control` and `assets_cache_control`. Add or remove always-revalidate root files via `html_path_overrides` (pass `[]` to opt out of the defaults). Set `cache_control_enabled = false` to skip the function entirely and delegate `Cache-Control` to S3 object metadata or to a caller-supplied `response_headers_policy_id`. The `response_headers_policy_id` variable is for orthogonal headers (HSTS, CSP, COOP/COEP, etc.) — it coexists with the cache-control function and shouldn't carry `Cache-Control` itself.

> **Why no `s-maxage` or `stale-while-revalidate` in the HTML default:** headers written in viewer-response are invisible to CloudFront's own caching — edge TTLs come from origin headers (S3 sends none, so the cache policy's default TTL applies) and edge freshness comes from the versioned cache key. The only consumer of this header is the browser, and browsers ignore `s-maxage`. `stale-while-revalidate` *is* honored by browsers, which is exactly why it's excluded: it would let the browser show a stale page on the first navigation after a version flip, buying nothing in return since revalidation is already a cheap edge-answered `304`.

> **Why the function lives in viewer-response, not viewer-request:** CloudFront resolves which cache behavior (and therefore which response-headers policy) to use from the **original viewer URI**, before any viewer-request function runs. SPA routes like `/dashboard` have no extension, so a static `*.html` ordered behavior cannot match them; the default behavior's response-headers policy is the only thing that ever gets attached. That's how [ENG-4785](https://linear.app/flightcontrol/issue/ENG-4785/) happened — the immutable assets policy on the default behavior leaked onto every HTML response. Setting `Cache-Control` in viewer-response sidesteps cache-behavior matching entirely and keys off the rewritten URI shape, where HTML vs asset is unambiguous from the file extension.

## 404 handling

Missing objects return **real 404s**, not 403s: the bucket policy grants the CloudFront service principal `s3:ListBucket` alongside `s3:GetObject`, so S3 can distinguish "key does not exist" (404) from "access denied" (403). A genuine 403 from this site therefore always means the request was *blocked* (e.g. by WAF), never "file missing". There is no listing exposure — the rewriter pins every URI to `/<version>/<key>`, so S3 only ever receives object GETs.

When `error_document` is set (default `"404.html"`), a CloudFront custom error response serves that page as the 404 body while keeping the **404 status** — never a 200, so search engines don't index error pages, and SPA asset misses fail loudly instead of receiving HTML.

**Ship the page in your build assets**: emit `404.html` at the root of the build output (the default convention in Astro, Hugo, Eleventy, SvelteKit, Next.js export, …). One wrinkle: CloudFront fetches the error page directly from the origin *without* running the viewer-request rewrite, so the key resolves at the **bucket root**, outside version prefixes. Copy it there when promoting a version:

```bash
aws s3 cp "s3://$BUCKET/$VERSION/404.html" "s3://$BUCKET/404.html"
```

If the root key doesn't exist, viewers still get a correct 404 status — just with a plain body. The error page path gets a dedicated cache behavior pinned to the managed CachingDisabled policy, so it never inherits the default behavior's long edge TTL: a changed 404 page is served immediately for URLs that don't yet have a cached 404 response, while URLs that already have a cached 404 response refresh after `error_caching_min_ttl` (default 1 day) or on invalidation of that path. One caveat: hosts pinned to older versions via KVS share the most recently promoted 404 page. Set `error_document = ""` to disable the custom page entirely (null applies the default — null means "use default" in Terraform); `error_caching_min_ttl` (default 86400 — 1 day) controls how long the edge caches 404 responses and applies whether or not the custom page is enabled.

## Custom response headers (security, CORS, etc.)

For everything *other than* `Cache-Control` — HSTS, CSP, X-Frame-Options, Referrer-Policy, X-Content-Type-Options, CORS, custom headers, header stripping — there are three layers. Precedence on the default behavior: caller-supplied `response_headers_policy_id` > module-managed `response_headers_policy` > AWS-managed policy selected by `response_headers_presets`.

### Default: AWS-managed presets via `response_headers_presets`

CloudFront allows exactly one response-headers policy per cache behavior, so preset combinations map onto the single AWS-managed policy that covers them:

| `response_headers_presets` | Managed policy attached |
|---|---|
| `["security_headers"]` (default) | `SecurityHeadersPolicy` — HSTS, `X-Content-Type-Options: nosniff`, `X-Frame-Options: SAMEORIGIN`, `Referrer-Policy: strict-origin-when-cross-origin`, `X-XSS-Protection` |
| `["cors"]` | `SimpleCORS` — `Access-Control-Allow-Origin: *` for simple requests |
| `["cors_preflight"]` | `CORS-With-Preflight` — CORS from any origin incl. `OPTIONS` preflight |
| `["security_headers", "cors"]` | `CORS-and-SecurityHeadersPolicy` |
| `["security_headers", "cors_preflight"]` | `CORS-with-preflight-and-SecurityHeadersPolicy` |
| `[]` | none |

`cors_preflight` supersedes `cors` when both are selected (the preflight policies are supersets of SimpleCORS). Pass `[]` if the site must be embeddable in cross-origin iframes (SAMEORIGIN blocks that) or if you want no policy at all.

### Module-managed (declarative): `response_headers_policy`

```hcl
module "site" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//hosting/static_site?ref=v1.0.0"

  name = "my-app"

  distributions = {
    main = {
      aliases             = ["app.example.com"]
      acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc-123"
    }
  }

  response_headers_policy = {
    security_headers_config = {
      strict_transport_security = {
        access_control_max_age_sec = 63072000 # 2 years
        include_subdomains         = true
        preload                    = true
      }
      content_security_policy = {
        content_security_policy = "default-src 'self'; script-src 'self' https://plausible.io; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' https://plausible.io"
      }
      content_type_options = {}
      frame_options = {
        frame_option = "DENY"
      }
      referrer_policy = {
        referrer_policy = "strict-origin-when-cross-origin"
      }
    }

    custom_headers = [
      {
        header = "Permissions-Policy"
        value  = "camera=(), microphone=(), geolocation=()"
      },
      {
        header = "Cross-Origin-Opener-Policy"
        value  = "same-origin"
      },
    ]

    remove_headers = ["Server", "X-Powered-By"]
  }
}
```

The module creates an `aws_cloudfront_response_headers_policy` from this configuration and attaches it to the default cache behavior alongside the cache-control function.

### Caller-supplied: `response_headers_policy_id`

For org-wide CSP/security baselines managed centrally, pass the existing policy id directly:

```hcl
module "site" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//hosting/static_site?ref=v1.0.0"

  name = "my-app"

  distributions = { main = { ... } }

  response_headers_policy_id = data.aws_cloudfront_response_headers_policy.org_security.id
}
```

`response_headers_policy_id` and `response_headers_policy` can both be set — the caller-supplied id wins on the default behavior, but the module-managed policy is still created and exposed via `module_response_headers_policy_id` so you can attach it elsewhere. Setting either one replaces the `response_headers_presets` default, so carry equivalent security headers in your own policy.

> **Don't put `Cache-Control` in `custom_headers` with `override = true`** unless you intentionally want to overwrite what the cache-control function set. Response-headers policies apply *after* CloudFront Functions, so a policy-set value with override beats the function. The whole point of the function is to discriminate HTML from assets at the URI level, which a static policy can't do.

## Requirements

| Name | Version |
|---|---|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 5.0 |

No external apply-time tools required.

## Inputs

### Required

| Name | Description | Type |
|---|---|---|
| name | Name prefix for all resources; also used as the hosting bucket name (must be globally unique). | `string` |

### General

| Name | Description | Type | Default |
|---|---|---|---|
| routing | URI rewrite style: `spa` or `filesystem`. | `string` | `"spa"` |
| default_version | Fallback version prefix when KVS has neither host nor `active` entries. Also seeds `active` on first apply. | `string` | `"main"` |
| distributions | Map of CloudFront distributions sharing the same origin. | `map(object)` | `{ main = {} }` |
| tags | Tags to apply to all resources. | `map(string)` | `{}` |

### Distribution

| Name | Description | Type | Default |
|---|---|---|---|
| price_class | CloudFront price class. | `string` | `"PriceClass_100"` |
| minimum_protocol_version | Minimum TLS version when using a custom ACM cert. | `string` | `"TLSv1.2_2021"` |
| geo_restriction_type | `none`, `whitelist`, `blacklist`. | `string` | `"none"` |
| geo_restriction_locations | ISO-3166-1-alpha-2 country codes. | `list(string)` | `[]` |
| web_acl_id | WAFv2 (global scope) Web ACL ARN. | `string` | `null` |
| deployment_wait_enabled | Wait for distributions to deploy on apply. | `bool` | `true` |

### Hosting Bucket

| Name | Description | Type | Default |
|---|---|---|---|
| bucket_versioning_enabled | Enable S3 versioning on the hosting bucket. | `bool` | `true` |
| bucket_force_destroy_enabled | Allow destroy of a non-empty bucket. | `bool` | `false` |
| bucket_lifecycle_rules | Lifecycle rules. | `list(object)` | expire noncurrent after 30d, abort multipart after 7d |
| kms_key_arn | SSE-KMS key ARN; null = SSE-S3 (AES256). | `string` | `null` |

### Origin

| Name | Description | Type | Default |
|---|---|---|---|
| origin_shield_enabled | Enable Origin Shield; the region is derived from the bucket region (nearest supported region when CloudFront doesn't offer Origin Shield there). | `bool` | `false` |
| origin_shield_region | Override the derived Origin Shield region. Only used when `origin_shield_enabled = true`. | `string` | `null` (auto) |
| additional_origin_headers | Extra custom headers sent to S3. | `list(object({name, value}))` | `[]` |

### Cache Behavior

| Name | Description | Type | Default |
|---|---|---|---|
| cache_policy_id | Cache policy ID for the default behavior. | `string` | `null` (module-managed 1-year policy) |
| origin_request_policy_id | Origin request policy ID. | `string` | AWS-managed CORS-S3Origin |
| response_headers_presets | AWS-managed response-header sets (`security_headers`, `cors`, `cors_preflight`) attached when no other response-headers policy is configured. Combinations map to AWS's managed combo policies. | `list(string)` | `["security_headers"]` |
| response_headers_policy_id | Externally-managed response-headers policy ID (e.g. an org-wide CSP). Wins over `response_headers_policy` when both are set. | `string` | `null` |
| response_headers_policy | Declarative module-managed response-headers policy: HSTS, CSP, X-Frame-Options, Referrer-Policy, CORS, custom headers, removed headers. See README for the full shape and an example. | `object(...)` | `null` |
| no_cache_paths | Path patterns served with CachingDisabled. | `list(string)` | `[]` |
| default_root_object | Object name for `/` requests. | `string` | `"index.html"` |
| error_document | Bucket-root key served with a 404 status when an object is missing. Empty string disables the custom page. | `string` | `"404.html"` |
| error_caching_min_ttl | Seconds CloudFront caches 404 responses at the edge. | `number` | `86400` |
| cache_control_enabled | Attach the viewer-response Cache-Control function. | `bool` | `true` |
| html_cache_control | Cache-Control value for HTML responses (no extension, `.html`/`.htm`, dotted segments, or `html_path_overrides`). | `string` | `"public, max-age=0, must-revalidate"` |
| assets_cache_control | Cache-Control value for hashed asset responses (any non-html file extension not in `html_path_overrides`). | `string` | `"public, max-age=31536000, immutable"` |
| html_path_overrides | Exact-match viewer URIs that always get `html_cache_control` regardless of extension. Defaults cover service-worker/PWA/SEO files. | `list(string)` | `["/service-worker.js", "/sw.js", "/manifest.json", "/manifest.webmanifest", "/favicon.ico", "/robots.txt", "/sitemap.xml"]` |

### KeyValueStore

| Name | Description | Type | Default |
|---|---|---|---|
| kvs_initial_data | Seed entries (`host -> version` or `"active" -> version`). Subsequent edits should happen via the AWS CLI from CI. | `map(string)` | `{}` |

### Logging

| Name | Description | Type | Default |
|---|---|---|---|
| logging_enabled | Enable CloudFront access logging. On by default with CloudWatch Logs delivery. | `bool` | `true` |
| logging_destination | Where access logs are delivered: `cloudwatch` (standard logging v2 into a module-managed CloudWatch Logs group) or `s3` (legacy standard logging). | `string` | `"cloudwatch"` |
| logging_bucket_creation_enabled | Create a new S3 bucket for logs. Only applies when `logging_destination = "s3"`. | `bool` | `false` |
| logging_bucket_domain_name | Existing logging bucket domain name. Only applies when `logging_destination = "s3"`. | `string` | `null` |
| logging_prefix | Base prefix for log files. Only applies when `logging_destination = "s3"`. | `string` | `""` |
| logging_retention_days | Days to retain logs: CloudWatch log group retention (`cloudwatch`) or S3 lifecycle expiry on the module-created bucket (`s3`). | `number` | `365` |

### Deploy Role

| Name | Description | Type | Default |
|---|---|---|---|
| deploy_role_creation_enabled | Create an IAM role for CI to assume. | `bool` | `false` |
| deploy_role_trust_policy | Trust policy JSON. Required when `deploy_role_creation_enabled = true`. | `string` | `null` |
| deploy_role_name | Override role name. | `string` | `"<name>-deploy"` |

## Outputs

| Name | Description |
|---|---|
| hosting_bucket_id | Name of the S3 hosting bucket. |
| hosting_bucket_arn | ARN of the S3 hosting bucket. |
| hosting_bucket_regional_domain_name | Regional domain name of the hosting bucket. |
| hosting_bucket_region | AWS region of the hosting bucket. |
| distribution_ids | Map of distribution key -> CloudFront distribution ID. |
| primary_distribution_id | CloudFront distribution ID of the primary distribution. |
| cloudfront_distribution_arns_map | Map of distribution key -> distribution ARN. |
| cloudfront_distribution_arns | List of all CloudFront distribution ARNs. |
| distribution_domain_names | Map of distribution key -> CloudFront domain name. |
| distribution_hosted_zone_ids | Map of distribution key -> Route53 zone ID for alias records. |
| primary_domain | Primary viewer-facing domain of the primary distribution: first alias if configured, otherwise the CloudFront domain name. |
| distribution_primary_domains | Map of distribution key -> primary domain (first alias, else CloudFront domain). |
| cloudfront_function_arn | ARN of the viewer-request rewriter function. |
| cache_control_function_arn | ARN of the viewer-response Cache-Control writer function. Null when `cache_control_enabled = false`. |
| cache_policy_id | ID of the cache policy attached to the default behavior (caller-supplied when set, otherwise module-managed). |
| response_headers_policy_id | ID of the response-headers policy attached to the default behavior (caller-supplied id when set, otherwise the module-managed one, otherwise null). |
| module_response_headers_policy_id | ID of the module-managed response-headers policy. Null when `var.response_headers_policy` is null. |
| cloudfront_keyvaluestore_arn | ARN of the KeyValueStore. |
| key_value_store_id | ID of the KeyValueStore. |
| default_version | Apply-time fallback version (also seeded into `active`). |
| deploy_role_arn | ARN of the deploy role (null unless created). |
| deploy_role_name | Name of the deploy role. |
| set_active_version_command | Bash snippet that flips the `active` KVS key to `$VERSION`. |
| invalidation_commands | Map of distribution key -> ready-to-run `aws cloudfront create-invalidation`. Rarely needed. |
| access_log_group_name | Name of the CloudWatch Logs group receiving CloudFront access logs. Null unless CloudWatch logging is enabled. |
| access_log_group_arn | ARN of the CloudWatch Logs access-log group. Null unless CloudWatch logging is enabled. |

## Security Considerations

- Hosting bucket has all four S3 public access block settings enabled by default (inherited from `storage/s3`).
- CloudFront uses OAC, not OAI — supports SSE-KMS and Object Lambda.
- Bucket policy grants `s3:GetObject` and `s3:ListBucket` only to `cloudfront.amazonaws.com` scoped to the specific distribution ARNs created by this module (defense in depth). `ListBucket` exists so missing keys return 404 instead of 403. It carries no `s3:prefix` condition because S3's implicit 404-vs-403 check evaluates `ListBucket` without prefix context — a condition would fail closed and reintroduce 403s. Listing exposure is prevented at the distribution level instead: `default_root_object` intercepts `/` before any function runs, and the origin request policy forwards no query strings, so a request shape that returns a listing can never reach S3 (see data.tf for the full rationale).
- The AWS-managed `SecurityHeadersPolicy` (HSTS, nosniff, X-Frame-Options SAMEORIGIN, Referrer-Policy) is attached by default; remove it via `response_headers_presets = []` or supersede it with your own policy.
- Optional deploy role uses a fully user-supplied trust policy — no implicit cross-account trust.
- TLS 1.2+ enforced on the viewer side (`minimum_protocol_version` defaults to `TLSv1.2_2021`).
- HTTP -> HTTPS redirect is the default viewer protocol policy.

## Notes

- **Build is your job**: this module does not run a build step. CI produces a `dist/` directory and `aws s3 sync`s it to `s3://<bucket>/<version>/`.
- **First deploy**: with `default_version = "main"`, a fresh apply works as soon as you sync to `s3://<bucket>/main/`. No KVS edit needed for the very first cutover.
- **404 pages**: emit `404.html` at the root of the build output and copy it to the bucket root at promotion (see [404 handling](#404-handling)).
- **First request is slow**: CloudFront distributions take 5-15 minutes to deploy globally. `deployment_wait_enabled = true` (default) blocks `tofu apply` until ready; set to `false` for faster iteration.
- **KVS updates**: only the seed entries are managed via Terraform. Subsequent additions/deletions (preview hosts, `active` flips) belong in CI.
- **Route53 records**: create externally with [`networking/route53`](../../networking/route53) using the `distribution_domain_names` and `distribution_hosted_zone_ids` outputs.
- **ACM certificates**: create externally with [`security/acm_certificate`](../../security/acm_certificate) using a `us_east_1` provider alias.
