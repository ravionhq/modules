################################################################################
# Sandbox Router
#
# Ravion reads the sandbox_router_* outputs to route previews of this module
# instance's wildcard domain through the router.
################################################################################

output "sandbox_router_id" {
  description = "The router's identity: the module instance id it enrolls with."
  value       = var.module_instance_id
}

output "sandbox_router_dns_name" {
  description = "The DNS name of the load balancer in front of the router. The wildcard domain points at it."
  value       = aws_lb.this.dns_name
}

output "sandbox_router_zone_id" {
  description = "The canonical hosted zone ID of the load balancer (for Route 53 alias records)."
  value       = aws_lb.this.zone_id
}

output "sandbox_router_load_balancer_arn" {
  description = "The ARN of the load balancer in front of the router."
  value       = aws_lb.this.arn
}

output "sandbox_router_security_group_id" {
  description = "The ID of the router instance's security group. Sandbox hosts allow preview traffic from it."
  value       = aws_security_group.router.id
}

output "sandbox_host_security_group_ids" {
  description = "The IDs of the sandbox host security groups that admit the router on the preview port range. The router reaches sandbox hosts in these groups only."
  value       = sort([for rule in aws_vpc_security_group_ingress_rule.sandbox_hosts : rule.security_group_id])
}

################################################################################
# Domain
################################################################################

output "wildcard_domain_name" {
  description = "The apex previews are served under: every preview is a hostname one label below it."
  value       = ravion_aws_acm_certificate.this.domain_name
}

output "certificate_arn" {
  description = "The ARN of the wildcard certificate on the TLS listener."
  value       = ravion_aws_acm_certificate.this.arn
}

output "custom_domain_names" {
  description = "The custom wildcard domains previews can be served under, beside wildcard_domain_name."
  value       = local.custom_domains
}

output "custom_certificate_arn" {
  description = "The ARN of the certificate that covers the custom domains on the TLS listener. Null when there are none."
  value       = length(local.custom_domains) > 0 ? ravion_aws_acm_certificate.custom[0].arn : null
}

################################################################################
# Load Balancer and Router
################################################################################

output "load_balancer_security_group_id" {
  description = "The ID of the load balancer's security group."
  value       = aws_security_group.load_balancer.id
}

output "autoscaling_group_name" {
  description = "The name of the Auto Scaling group that keeps the router instance running."
  value       = aws_autoscaling_group.router.name
}

output "image_id" {
  description = "The AMI new router instances boot."
  value       = data.aws_ami.router.id
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
