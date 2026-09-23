################################################################################
# Hosting Bucket
################################################################################

output "hosting_bucket_id" {
  description = "Name of the S3 hosting bucket."
  value       = module.hosting.bucket_id
}

output "hosting_bucket_arn" {
  description = "ARN of the S3 hosting bucket."
  value       = module.hosting.bucket_arn
}

output "hosting_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 hosting bucket (used as CloudFront origin)."
  value       = module.hosting.bucket_regional_domain_name
}

output "hosting_bucket_region" {
  description = "AWS region where the hosting bucket lives."
  value       = module.hosting.bucket_region
}

################################################################################
# CloudFront Distributions
################################################################################

output "distribution_ids" {
  description = "Map of distribution key -> CloudFront distribution ID."
  value       = module.cdn.distribution_ids
}

output "cloudfront_distribution_arns_map" {
  description = "Map of distribution key -> CloudFront distribution ARN."
  value       = module.cdn.distribution_arns
}

output "cloudfront_distribution_arns" {
  description = "List of all CloudFront distribution ARNs."
  value       = values(module.cdn.distribution_arns)
}

output "distribution_domain_names" {
  description = "Map of distribution key -> CloudFront distribution domain name (e.g. 'd123.cloudfront.net')."
  value       = module.cdn.distribution_domain_names
}

output "distribution_hosted_zone_ids" {
  description = "Map of distribution key -> CloudFront Route53 zone ID for alias records."
  value       = module.cdn.distribution_hosted_zone_ids
}

output "primary_distribution_id" {
  description = "CloudFront distribution ID of the primary distribution ('main', or the lexically first key). Used for CloudWatch metric dimensions."
  value       = module.cdn.distribution_ids[local.primary_distribution_key]
}

output "primary_domain" {
  description = "Primary viewer-facing domain of the primary distribution ('main', or the lexically first key): the first alias when aliases are configured, otherwise the CloudFront domain name (e.g. 'd123.cloudfront.net')."
  value = (
    length(var.distributions[local.primary_distribution_key].aliases) > 0
    ? var.distributions[local.primary_distribution_key].aliases[0]
    : module.cdn.distribution_domain_names[local.primary_distribution_key]
  )
}

output "distribution_primary_domains" {
  description = "Map of distribution key -> primary domain: the first alias when aliases are configured, otherwise the CloudFront domain name."
  value = {
    for k, d in var.distributions :
    k => length(d.aliases) > 0 ? d.aliases[0] : module.cdn.distribution_domain_names[k]
  }
}

################################################################################
# Edge / Versioning
################################################################################

output "cloudfront_function_arn" {
  description = "ARN of the viewer-request rewriter function."
  value       = aws_cloudfront_function.rewrite.arn
}

output "cache_control_function_arn" {
  description = "ARN of the viewer-response Cache-Control writer function. Null when cache_control_enabled = false."
  value       = try(aws_cloudfront_function.cache_control[0].arn, null)
}

output "cache_policy_id" {
  description = "ID of the cache policy attached to the default behavior. Caller-supplied `cache_policy_id` when set, otherwise the module-managed 1-year policy."
  value       = local.effective_cache_policy_id
}

output "response_headers_policy_id" {
  description = "ID of the response-headers policy attached to the default cache behavior. Caller-supplied `response_headers_policy_id` when set, otherwise the module-managed policy created from `response_headers_policy`, otherwise null."
  value       = local.effective_response_headers_policy_id
}

output "module_response_headers_policy_id" {
  description = "ID of the module-managed response-headers policy created from `var.response_headers_policy`. Null when that variable is null. Useful for attaching the same policy to other distributions or behaviors outside this module."
  value       = local.module_response_headers_policy_id
}

output "cloudfront_keyvaluestore_arn" {
  description = "ARN of the CloudFront KeyValueStore that holds host -> version mappings."
  value       = aws_cloudfront_key_value_store.this.arn
}

output "key_value_store_id" {
  description = "ID of the CloudFront KeyValueStore."
  value       = aws_cloudfront_key_value_store.this.id
}

output "default_version" {
  description = "Version prefix the function falls back to when KVS has no host or active entry. The 'active' KVS key is seeded to this on first apply."
  value       = var.default_version
}

################################################################################
# Deploy Role
################################################################################

output "deploy_role_arn" {
  description = "ARN of the IAM role CI assumes to deploy. Null unless deploy_role_creation_enabled = true."
  value       = var.deploy_role_creation_enabled ? aws_iam_role.deploy[0].arn : null
}

output "deploy_role_name" {
  description = "Name of the IAM deploy role. Null unless deploy_role_creation_enabled = true."
  value       = var.deploy_role_creation_enabled ? aws_iam_role.deploy[0].name : null
}

################################################################################
# Convenience
################################################################################

output "set_active_version_command" {
  description = "Bash snippet that flips the 'active' KVS key to a new version. Set VERSION before running. Reads the current KVS ETag with describe-key-value-store and passes it via --if-match (KVS requires optimistic concurrency)."
  value       = <<-EOT
    KVS_ARN=${aws_cloudfront_key_value_store.this.arn}
    ETAG=$(aws cloudfront-keyvaluestore describe-key-value-store --kvs-arn $KVS_ARN --query ETag --output text)
    aws cloudfront-keyvaluestore put-key --kvs-arn $KVS_ARN --if-match $ETAG --key active --value $VERSION
  EOT
}

output "invalidation_commands" {
  description = "Map of distribution key -> ready-to-run AWS CLI command that invalidates the entire distribution. Versioned deploys do not need invalidations (each promotion produces a fresh cache key); kept as an escape hatch."
  value = {
    for k, id in module.cdn.distribution_ids :
    k => "aws cloudfront create-invalidation --distribution-id ${id} --paths '/*'"
  }
}

################################################################################
# Logging
################################################################################

output "access_log_group_name" {
  description = "Name of the CloudWatch Logs group receiving CloudFront access logs. Null unless logging_enabled is true and logging_destination is 'cloudwatch'."
  value       = module.cdn.access_log_group_name
}

output "access_log_group_arn" {
  description = "ARN of the CloudWatch Logs access-log group. Null unless CloudWatch logging is enabled."
  value       = module.cdn.access_log_group_arn
}

################################################################################
# Account & Region
################################################################################

output "aws_account_id" {
  description = "The AWS account ID where the resources are deployed."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "The AWS region where the resources are deployed."
  value       = local.region
}

output "cloudwatch_alarm_arns" {
  description = "CloudFront 5xx error-rate alarm ARNs keyed by distribution key."
  value       = { for key, alarm in aws_cloudwatch_metric_alarm.error_rate : key => alarm.arn }
}
