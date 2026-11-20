output "web_acl_arn" {
  description = "ARN of the web ACL. For a CloudFront target, set it as the distribution's web ACL (web_acl_id)."
  value       = aws_wafv2_web_acl.this.arn
}

output "web_acl_id" {
  description = "ID of the web ACL."
  value       = aws_wafv2_web_acl.this.id
}

output "web_acl_name" {
  description = "Name of the web ACL."
  value       = aws_wafv2_web_acl.this.name
}

output "scope" {
  description = "Scope of the web ACL: REGIONAL for load balancers, CLOUDFRONT for distributions."
  value       = local.scope
}

output "region" {
  description = "Region the web ACL lives in (us-east-1 for CloudFront)."
  value       = local.region
}

output "capacity" {
  description = "Web ACL capacity units the rules use (AWS allows 1,500 by default)."
  value       = aws_wafv2_web_acl.this.capacity
}

output "associated_alb_arns" {
  description = "Load balancers the web ACL is associated with."
  value       = sort([for association in aws_wafv2_web_acl_association.alb : association.resource_arn])
}

output "ip_set_arns" {
  description = "IP sets created for ip_allow_list and ip_block_list, by key (allow-ipv4, allow-ipv6, block-ipv4, block-ipv6)."
  value       = { for key, set in aws_wafv2_ip_set.this : key => set.arn }
}

output "custom_rule_group_arn" {
  description = "ARN of the rule group holding custom_rules_json (null without custom rules)."
  value       = try(aws_wafv2_rule_group.custom[0].arn, null)
}

output "logging_enabled" {
  description = "Whether the web ACL logs to logging_destination_arn."
  value       = var.logging_destination_arn != null
}
