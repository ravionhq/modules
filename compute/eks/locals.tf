locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "compute/eks"
  }

  tags = merge(local.default_tags, var.tags)

  node_subnet_ids = coalesce(var.node_subnet_ids, var.subnet_ids)

  # Approved control-plane egress. These are trust-policy constraints, not
  # relay networking rules or caller-configurable endpoint access CIDRs.
  ravion_access_source_cidrs = [
    "35.165.172.23/32",
    "52.38.126.172/32",
    "54.200.59.143/32",
    "54.214.167.211/32",
    "50.112.69.57/32",
    "184.33.144.157/32",
  ]

  ravion_access_assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "TrustRavionIntegrationRole"
      Effect    = "Allow"
      Action    = ["sts:AssumeRole", "sts:SetSourceIdentity"]
      Principal = { AWS = var.ravion_integration_role_arn }
      Condition = {
        IpAddress = { "aws:SourceIp" = local.ravion_access_source_cidrs }
      }
    }]
  })
}
