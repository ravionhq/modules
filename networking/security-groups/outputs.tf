################################################################################
# Security Group
################################################################################

output "security_group_id" {
  description = "The ID of the security group."
  value       = aws_security_group.this.id
}

output "security_group_arn" {
  description = "The ARN of the security group."
  value       = aws_security_group.this.arn
}

output "security_group_name" {
  description = "The name of the security group."
  value       = aws_security_group.this.name
}

output "security_group_vpc_id" {
  description = "The VPC ID of the security group."
  value       = aws_security_group.this.vpc_id
}

output "security_group_owner_id" {
  description = "The owner ID (AWS account ID) of the security group."
  value       = aws_security_group.this.owner_id
}

################################################################################
# Ingress Rules
################################################################################

output "ingress_rule_ids" {
  description = "Map of ingress rule keys to their IDs."
  value       = { for k, v in aws_vpc_security_group_ingress_rule.this : k => v.id }
}

output "ingress_rule_arns" {
  description = "Map of ingress rule keys to their ARNs."
  value       = { for k, v in aws_vpc_security_group_ingress_rule.this : k => v.arn }
}

################################################################################
# Egress Rules
################################################################################

output "egress_rule_ids" {
  description = "Map of egress rule keys to their IDs."
  value       = { for k, v in aws_vpc_security_group_egress_rule.this : k => v.id }
}

output "egress_rule_arns" {
  description = "Map of egress rule keys to their ARNs."
  value       = { for k, v in aws_vpc_security_group_egress_rule.this : k => v.arn }
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

output "all_egress_rule_ids" {
  description = "IDs of the allow-all egress rules (IPv4 then IPv6) created when all_egress_enabled is true. Empty otherwise."
  value = concat(
    [for r in aws_vpc_security_group_egress_rule.allow_all_ipv4 : r.id],
    [for r in aws_vpc_security_group_egress_rule.allow_all_ipv6 : r.id],
  )
}
