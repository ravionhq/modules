################################################################################
# Distribution
################################################################################

output "distribution_ids" {
  description = "A map of distribution key to CloudFront distribution ID."
  value       = { for k, v in aws_cloudfront_distribution.this : k => v.id }
}

output "cache_policy_id" {
  description = "The ID of the cache policy attached to the default behavior, including the module-managed Accept-aware policy when enabled."
  value       = local.effective_default_cache_policy_id
}

output "distribution_arns" {
  description = "A map of distribution key to CloudFront distribution ARN."
  value       = { for k, v in aws_cloudfront_distribution.this : k => v.arn }
}

output "distribution_domain_names" {
  description = "A map of distribution key to CloudFront distribution domain name."
  value       = { for k, v in aws_cloudfront_distribution.this : k => v.domain_name }
}

output "distribution_hosted_zone_ids" {
  description = "A map of distribution key to CloudFront Route 53 zone ID for alias records."
  value       = { for k, v in aws_cloudfront_distribution.this : k => v.hosted_zone_id }
}

output "distribution_statuses" {
  description = "A map of distribution key to current status of the distribution."
  value       = { for k, v in aws_cloudfront_distribution.this : k => v.status }
}

output "distribution_etags" {
  description = "A map of distribution key to current version of the distribution's information."
  value       = { for k, v in aws_cloudfront_distribution.this : k => v.etag }
}

################################################################################
# Edge Redirects
################################################################################

output "redirect_function_arn" {
  description = "The ARN of the managed viewer-request redirect function, or null when redirect rules are disabled."
  value       = try(aws_cloudfront_function.redirect[0].arn, null)
}

output "redirect_function_name" {
  description = "The name of the managed viewer-request redirect function, or null when redirect rules are disabled."
  value       = try(aws_cloudfront_function.redirect[0].name, null)
}

output "distribution_id" {
  description = "The ID of the CloudFront distribution when exactly one distribution is created (null otherwise)."
  value       = length(aws_cloudfront_distribution.this) == 1 ? values(aws_cloudfront_distribution.this)[0].id : null
}

output "distribution_arn" {
  description = "The ARN of the CloudFront distribution when exactly one distribution is created (null otherwise)."
  value       = length(aws_cloudfront_distribution.this) == 1 ? values(aws_cloudfront_distribution.this)[0].arn : null
}

output "distribution_domain_name" {
  description = "The domain name of the CloudFront distribution when exactly one distribution is created (null otherwise)."
  value       = length(aws_cloudfront_distribution.this) == 1 ? values(aws_cloudfront_distribution.this)[0].domain_name : null
}

output "distribution_hosted_zone_id" {
  description = "The Route 53 hosted zone ID of the CloudFront distribution when exactly one distribution is created (null otherwise)."
  value       = length(aws_cloudfront_distribution.this) == 1 ? values(aws_cloudfront_distribution.this)[0].hosted_zone_id : null
}

################################################################################
# Origin Access Control
################################################################################

output "origin_access_control_ids" {
  description = "A map of origin_id to OAC ID for S3 origins."
  value       = { for k, v in aws_cloudfront_origin_access_control.this : k => v.id }
}

################################################################################
# VPC Origins
################################################################################

output "vpc_origin_ids" {
  description = "A map of origin_id to CloudFront VPC origin ID for VPC-enabled origins."
  value       = { for k, v in aws_cloudfront_vpc_origin.this : k => v.id }
}

output "vpc_origin_arns" {
  description = "A map of origin_id to CloudFront VPC origin ARN for VPC-enabled origins."
  value       = { for k, v in aws_cloudfront_vpc_origin.this : k => v.arn }
}

################################################################################
# Logging
################################################################################

output "logging_bucket_id" {
  description = "The ID of the logging S3 bucket. Null unless S3 logging is active with a module-created bucket."
  value       = try(aws_s3_bucket.logging[0].id, null)
}

output "logging_bucket_arn" {
  description = "The ARN of the logging S3 bucket. Null unless S3 logging is active with a module-created bucket."
  value       = try(aws_s3_bucket.logging[0].arn, null)
}

output "logging_bucket_domain_name" {
  description = "The domain name of the logging S3 bucket. Null unless S3 logging is active with a module-created bucket."
  value       = try(aws_s3_bucket.logging[0].bucket_domain_name, null)
}

output "access_log_group_name" {
  description = "Name of the CloudWatch Logs group receiving CloudFront access logs. Null unless logging_enabled is true and logging_destination is 'cloudwatch'."
  value       = try(aws_cloudwatch_log_group.access_logs[0].name, null)
}

output "access_log_group_arn" {
  description = "ARN of the CloudWatch Logs access-log group. Null unless CloudWatch logging is enabled."
  value       = try(aws_cloudwatch_log_group.access_logs[0].arn, null)
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
