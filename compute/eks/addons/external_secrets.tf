################################################################################
# External Secrets Operator (Helm)
#
# Bridges Ravion's reference-only secrets posture to Kubernetes: workloads
# reference a Secrets Manager secret or SSM parameter by ARN, and ESO
# materializes it into a Kubernetes Secret in the workload's namespace. Secret
# values never pass through Ravion, Helm values, or release history.
#
# Unlike Karpenter, the external-secrets chart renders its CRDs as ordinary
# templates (installCRDs, default on), so Helm upgrades them and no separate
# CRD chart is needed.
#
# All releases set upgrade_install so an apply adopts a same-named release
# already present in the cluster (e.g. left behind by a deleted module
# instance) instead of failing with "cannot re-use a name that is still in
# use".
################################################################################

resource "helm_release" "external_secrets" {
  count = var.eso_enabled ? 1 : 0

  name       = "external-secrets"
  namespace  = var.eso_namespace
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = var.eso_chart_version

  create_namespace = true
  upgrade_install  = true

  values = concat(
    [
      yamlencode({
        installCRDs = true
        # Must match the Pod Identity association created in
        # external_secrets_iam.tf, or the controller falls back to the node
        # role and every ExternalSecret fails with AccessDenied.
        serviceAccount = {
          create = true
          name   = var.eso_service_account
        }
      }),
    ],
    var.eso_helm_values,
  )

  # The controller reads AWS credentials on startup through the Pod Identity
  # Agent, so the association must exist first. Its Service also needs the
  # load balancer controller's admission webhook to be serving.
  depends_on = [
    aws_eks_pod_identity_association.external_secrets,
    helm_release.lb_controller,
  ]
}

################################################################################
# ClusterSecretStores
#
# Delivered as a local chart because the Helm provider is the only Kubernetes
# access this stack has, and because ClusterSecretStore is a CRD kind that
# cannot be applied until the operator release above has installed its CRDs
# and its validating webhook is serving.
#
# Two stores exist because ESO's AWS provider takes a single `service` per
# store: Secrets Manager and Parameter Store cannot share one. Both are
# cluster-scoped, so workloads in any namespace reference them by name with no
# per-namespace setup.
################################################################################

resource "helm_release" "external_secrets_stores" {
  count = var.eso_enabled && var.eso_cluster_secret_stores_creation_enabled ? 1 : 0

  name      = "external-secrets-stores"
  namespace = var.eso_namespace
  chart     = "${path.module}/charts/external-secrets-resources"

  upgrade_install = true

  values = [
    yamlencode({
      # No auth block is rendered: the store inherits the controller pod's
      # Pod Identity credentials via the AWS SDK default credential chain.
      region = data.aws_region.current.region
      secretsManagerStore = {
        name = var.eso_secrets_manager_store_name
      }
      parameterStore = {
        name = var.eso_parameter_store_store_name
      }
    }),
  ]

  depends_on = [helm_release.external_secrets]
}
