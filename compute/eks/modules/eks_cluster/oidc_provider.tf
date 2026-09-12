################################################################################
# OIDC Identity Provider
#
# Opt-in so consumer workloads can use IRSA (assume an IAM role from a
# Kubernetes service account JWT). Pod Identity is preferred for the helpers
# this module ships, but IRSA remains useful for app workloads where Pod
# Identity isn't supported by the upstream tooling.
################################################################################

resource "aws_iam_openid_connect_provider" "this" {
  count = var.oidc_provider_creation_enabled ? 1 : 0

  url             = local.oidc_issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc[0].certificates[0].sha1_fingerprint]

  tags = merge(local.tags, {
    Name = "${var.name}-oidc"
  })
}

# Preserve the provider's identity for existing IRSA users who opt in.
moved {
  from = aws_iam_openid_connect_provider.this
  to   = aws_iam_openid_connect_provider.this[0]
}
