################################################################################
# Application Load Balancer
################################################################################

output "alb_id" {
  description = "The ID of the Application Load Balancer."
  value       = aws_lb.this.id
}

output "alb_arn" {
  description = "The ARN of the Application Load Balancer."
  value       = aws_lb.this.arn
}

output "alb_arn_suffix" {
  description = "The ARN suffix of the ALB for use with CloudWatch Metrics."
  value       = aws_lb.this.arn_suffix
}

output "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "The canonical hosted zone ID of the ALB (for Route53 alias records)."
  value       = aws_lb.this.zone_id
}

################################################################################
# Listeners
################################################################################

output "http_listener_arn" {
  description = "The ARN of the HTTP listener (null if disabled)."
  value       = local.create_http_listener ? aws_lb_listener.http[0].arn : null
}

output "https_listener_arn" {
  description = "The ARN of the HTTPS listener (null if disabled)."
  value       = local.create_https_listener ? aws_lb_listener.https[0].arn : null
}

output "https_listener_certificate_arn" {
  description = "The default certificate ARN on the HTTPS listener (null if disabled)."
  value       = local.create_https_listener ? aws_lb_listener.https[0].certificate_arn : null
}

################################################################################
# Security Group
################################################################################

output "security_group_id" {
  description = "The ID of the ALB security group."
  value       = module.security_group.security_group_id
}

output "security_group_arn" {
  description = "The ARN of the ALB security group."
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

output "additional_certificate_arns" {
  description = "Certificate ARNs attached to the HTTPS listener via SNI (certificate_arns[1..]). Empty when at most one certificate is configured."
  value       = [for c in aws_lb_listener_certificate.additional : c.certificate_arn]
}
