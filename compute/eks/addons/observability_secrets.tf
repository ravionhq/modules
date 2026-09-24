################################################################################
# Vendor credentials — Secrets Manager ARNs in, Kubernetes Secrets out
#
# Every vendor credential this module needs is an ARN, never a value. The
# External Secrets Operator (external_secrets.tf) reads the secret with its own
# Pod Identity role and materializes it into a Kubernetes Secret in the
# collector namespace, and the collectors read it from there as an environment
# variable. No token ever passes through Ravion, a Helm value, a Terraform
# output, or Helm release history.
#
# Two kinds of Secret are rendered here:
#
#   1. COLLECTOR CREDENTIALS, in the observability namespace: the API key or
#      token each collector presents to the vendor when it ships.
#
#   2. PROXY CREDENTIALS, in Ravion Operator's namespace: the basic-auth pair the agent
#      presents when the dashboard queries an external store through it
#      (observability_ravion_operator.tf). Same ARN, different namespace and shape,
#      because a Secret cannot be mounted across namespaces.
#
# Delivered as a local chart because the Helm provider is this stack's only
# Kubernetes access, and because ExternalSecret is a CRD kind that cannot be
# applied before the operator release has installed its CRDs.
################################################################################

locals {
  # The collectors read these; keys match what the exporter configuration
  # references through ${env:...}.
  observability_collector_secrets = [
    for secret in local.vendor_secrets : {
      name      = secret.name
      namespace = local.observability_namespace
      template  = {}
      data = [{
        secretKey = secret.secret_key
        remoteRef = secret.remote_ref
      }]
    }
  ]

  observability_external_secrets = concat(
    local.observability_collector_secrets,
    local.ravion_operator_proxy_credential_secrets,
  )

  observability_secrets_enabled = length(local.observability_external_secrets) > 0
}

resource "helm_release" "observability_secrets" {
  count = local.observability_secrets_enabled ? 1 : 0

  name      = "ravion-observability-secrets"
  namespace = local.observability_namespace
  chart     = "${path.module}/charts/observability-secrets"

  create_namespace = true
  upgrade_install  = true

  values = [
    yamlencode({
      storeName       = var.eso_secrets_manager_store_name
      storeKind       = "ClusterSecretStore"
      refreshInterval = "1h"
      externalSecrets = local.observability_external_secrets
    }),
  ]

  # The CRDs and the ClusterSecretStore both come from the operator's releases.
  depends_on = [
    helm_release.external_secrets,
    helm_release.external_secrets_stores,
  ]

  lifecycle {
    precondition {
      condition     = var.eso_enabled && var.eso_cluster_secret_stores_creation_enabled
      error_message = "A vendor observability provider was selected with a secret ARN, but the External Secrets Operator is off (eso_enabled / eso_cluster_secret_stores_creation_enabled). Vendor credentials are materialized in-cluster by ESO and are never passed as Helm values, so the operator and its ClusterSecretStore are a hard requirement: turn External Secrets on, or drop the vendor provider."
    }
  }
}
