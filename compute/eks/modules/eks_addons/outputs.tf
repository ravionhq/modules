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

output "metrics_server_addon_arn" {
  description = "ARN of the Metrics Server EKS community add-on (null when disabled)."
  value       = var.metrics_server_enabled ? aws_eks_addon.metrics_server[0].arn : null
}

output "metrics_server_addon_version" {
  description = "Resolved version of the Metrics Server EKS community add-on (null when disabled)."
  value       = var.metrics_server_enabled ? aws_eks_addon.metrics_server[0].addon_version : null
}
