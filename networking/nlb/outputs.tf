################################################################################
# Network Load Balancer
################################################################################

output "load_balancer_name" {
  description = "The name of the load balancer, as passed in var.name."
  value       = aws_lb.this.name
}

output "nlb_id" {
  description = "The ID of the Network Load Balancer."
  value       = aws_lb.this.id
}

output "nlb_arn" {
  description = "The ARN of the Network Load Balancer."
  value       = aws_lb.this.arn
}

output "nlb_arn_suffix" {
  description = "The ARN suffix of the NLB for use with CloudWatch Metrics."
  value       = aws_lb.this.arn_suffix
}

output "nlb_dns_name" {
  description = "The DNS name of the Network Load Balancer."
  value       = aws_lb.this.dns_name
}

output "nlb_zone_id" {
  description = "The canonical hosted zone ID of the NLB (for Route53 alias records)."
  value       = aws_lb.this.zone_id
}

################################################################################
# Security Group
################################################################################

output "security_group_name" {
  description = "The name of the load balancer's security group (<name>-<type>)."
  value       = module.security_group.security_group_name
}

output "security_group_id" {
  description = "The ID of the NLB security group."
  value       = module.security_group.security_group_id
}

output "security_group_arn" {
  description = "The ARN of the NLB security group."
  value       = module.security_group.security_group_arn
}

################################################################################
# Access Logs
################################################################################

output "access_logs_bucket_name" {
  description = "The name of the S3 bucket for access logs (null if access logs disabled or using existing bucket)."
  value       = local.create_access_logs_bucket ? aws_s3_bucket.access_logs[0].id : null
}

output "access_logs_bucket_arn" {
  description = "The ARN of the S3 bucket for access logs (null if access logs disabled or using existing bucket)."
  value       = local.create_access_logs_bucket ? aws_s3_bucket.access_logs[0].arn : null
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
