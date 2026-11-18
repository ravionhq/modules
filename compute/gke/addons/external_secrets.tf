################################################################################
# External Secrets Operator
#
# Workloads reference a Secret Manager secret by name, and ESO materializes it
# into a Kubernetes Secret in the workload's namespace. Secret values never
# pass through Ravion, Helm values, or release history.
#
# The controller authenticates as its own Kubernetes service account through
# Workload Identity Federation for GKE: IAM grants Secret Manager access to
# that service account's principal directly.
################################################################################

# Left enabled on destroy: other workloads may read Secret Manager.
resource "google_project_service" "secretmanager" {
  count = var.eso_enabled ? 1 : 0

  project            = var.project_id
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

# Every secret in the project, unless eso_secret_ids narrows it.
resource "google_project_iam_member" "external_secrets" {
  count = var.eso_enabled && length(var.eso_secret_ids) == 0 ? 1 : 0

  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = local.eso_principal
}

resource "google_secret_manager_secret_iam_member" "external_secrets" {
  for_each = var.eso_enabled ? local.eso_secret_names : toset([])

  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = local.eso_principal
}

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
    [yamlencode({
      installCRDs = true
      # Must match local.eso_principal, or every ExternalSecret fails with
      # PermissionDenied.
      serviceAccount = {
        create = true
        name   = var.eso_service_account
      }
    })],
    # The controller, its webhook and its cert controller are three Deployments.
    var.addon_placement_enabled ? [yamlencode(merge(local.addon_pod_placement, {
      webhook        = local.addon_pod_placement
      certController = local.addon_pod_placement
    }))] : [],
    var.eso_helm_values,
  )

  depends_on = [
    google_project_service.secretmanager,
    google_project_iam_member.external_secrets,
    google_secret_manager_secret_iam_member.external_secrets,
  ]
}

################################################################################
# ClusterSecretStore
#
# Delivered as a local chart because the Helm provider is the only Kubernetes
# access this stack has, and because ClusterSecretStore is a CRD kind that
# cannot be applied until the operator release above has installed its CRDs
# and its validating webhook is serving.
################################################################################

resource "helm_release" "external_secrets_store" {
  count = var.eso_enabled && var.eso_cluster_secret_store_creation_enabled ? 1 : 0

  name      = "external-secrets-store"
  namespace = var.eso_namespace
  chart     = "${path.module}/charts/external-secrets-resources"
  # Pinned so a Chart.yaml bump shows in the plan.
  version = yamldecode(file("${path.module}/charts/external-secrets-resources/Chart.yaml")).version

  upgrade_install = true

  values = [yamlencode({
    name              = var.eso_cluster_secret_store_name
    projectID         = var.project_id
    allowedNamespaces = local.eso_allowed_namespaces
  })]

  # An unconditioned ClusterSecretStore is usable from every namespace, so any
  # principal that can create pods could read every secret the controller can.
  lifecycle {
    precondition {
      condition     = length(local.eso_allowed_namespaces) > 0
      error_message = "The External Secrets cluster store would be usable from every namespace. Set eso_allowed_namespaces to the namespaces that may read secrets, or set eso_cluster_secret_store_creation_enabled = false and create your own stores."
    }
  }

  depends_on = [helm_release.external_secrets]
}
