################################################################################
# Apps
#
# The module definition's apps block hands these to Ravion: the domains the
# apps are served under, the load balancer that serves them, and what Ravion
# launches the router with.
################################################################################

output "wildcard_domain_name" {
  description = "The apex apps are served under: every app URL is a hostname one label below it."
  value       = ravion_aws_acm_certificate.this.domain_name
}

output "custom_domain_apexes" {
  description = "The custom wildcard domains without their *., in the order given: apps are also served one label below each."
  value       = [for domain in local.custom_domains : trimprefix(domain, "*.")]
}

output "tls_listener_arn" {
  description = "The ARN of the TLS listener. Ravion attaches the certificate of each app's own domains to it."
  value       = aws_lb_listener.tls.arn
}

output "router_subnet_ids" {
  description = "The subnets Ravion may launch the router instance in."
  value       = var.router_subnet_ids
}

output "router_security_group_id" {
  description = "The ID of the router's security group. Ravion launches the router instance in it."
  value       = aws_security_group.router.id
}

output "router_instance_profile_name" {
  description = "The name of the instance profile Ravion launches the router instance with. Its role has the same name."
  value       = aws_iam_instance_profile.router.name
}

output "traffic_target_group_arn" {
  description = "The ARN of the target group the TLS listener forwards app traffic to. Ravion registers the router instance in it."
  value       = aws_lb_target_group.traffic.arn
}

output "redirect_target_group_arn" {
  description = "The ARN of the target group the HTTP listener forwards to, which the router answers with a redirect to HTTPS. Ravion registers the router instance in it."
  value       = aws_lb_target_group.redirect.arn
}

################################################################################
# Domain
################################################################################

output "certificate_arn" {
  description = "The ARN of the wildcard certificate on the TLS listener."
  value       = ravion_aws_acm_certificate.this.arn
}

output "custom_domain_names" {
  description = "The custom wildcard domains attached to the load balancer, beside wildcard_domain_name."
  value       = local.custom_domains
}

output "custom_certificate_arn" {
  description = "The ARN of the certificate that covers the custom domains on the TLS listener. Null when there are none."
  value       = length(local.custom_domains) > 0 ? ravion_aws_acm_certificate.custom[0].arn : null
}

################################################################################
# Load Balancer
################################################################################

output "load_balancer_arn" {
  description = "The ARN of the load balancer in front of the router."
  value       = aws_lb.this.arn
}

output "load_balancer_dns_name" {
  description = "The DNS name of the load balancer. The wildcard domain points at it."
  value       = aws_lb.this.dns_name
}

output "load_balancer_zone_id" {
  description = "The canonical hosted zone ID of the load balancer (for Route 53 alias records)."
  value       = aws_lb.this.zone_id
}

output "load_balancer_security_group_id" {
  description = "The ID of the load balancer's security group."
  value       = aws_security_group.load_balancer.id
}

output "load_balancer_arn_suffix" {
  description = "The load balancer's ARN suffix, the LoadBalancer dimension of its AWS/NetworkELB metrics."
  value       = aws_lb.this.arn_suffix
}

output "traffic_target_group_arn_suffix" {
  description = "The traffic target group's ARN suffix, the TargetGroup dimension of the router's health metrics in AWS/NetworkELB."
  value       = aws_lb_target_group.traffic.arn_suffix
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
