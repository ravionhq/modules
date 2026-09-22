################################################################################
# Local Values
################################################################################

locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "compute/eks/modules/eks_addons"
  }

  tags = merge(local.default_tags, var.tags)
}
