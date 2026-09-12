################################################################################
# CoreDNS
################################################################################

output "coredns_addon_arn" {
  description = "ARN of the coredns EKS add-on."
  value       = aws_eks_addon.coredns.arn
}

output "coredns_addon_version" {
  description = "Resolved version of the coredns EKS add-on."
  value       = aws_eks_addon.coredns.addon_version
}
