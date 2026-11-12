################################################################################
# Temporal
#
# Two releases in the same namespace:
#
#   1. temporal-resources (a local chart): the database password Secret (through
#      the External Secrets Operator), the RDS CA bundle, the private CA and
#      certificates, the PriorityClass, the dedicated NodePool, the network
#      policies and the metrics forwarder. Installed first, because the
#      Temporal pods mount the Secret, the CA bundle and the certificates.
#
#   2. The upstream temporalio/helm-charts `temporal` chart: frontend, history,
#      matching and worker services, the Web UI, the admin tools, the schema
#      job that creates and migrates both databases, and the job that creates
#      the Temporal namespaces.
#
# Both releases set upgrade_install so an apply adopts a same-named release
# already in the cluster instead of failing with "cannot re-use a name that is
# still in use".
################################################################################

resource "helm_release" "temporal_resources" {
  name      = local.resources_release_name
  namespace = var.namespace
  chart     = "${path.module}/charts/temporal-resources"
  # Pinned so a Chart.yaml bump shows in the plan.
  version          = yamldecode(file("${path.module}/charts/temporal-resources/Chart.yaml")).version
  create_namespace = var.namespace_creation_enabled
  upgrade_install  = true

  values = [yamlencode(local.resources_values)]

  lifecycle {
    precondition {
      condition     = startswith(local.database_engine, "aurora-postgresql")
      error_message = "The database cluster runs ${local.database_engine}. This module supports Aurora PostgreSQL only."
    }
    precondition {
      condition     = !local.database_external_secret || var.database_password_secret_arn != null
      error_message = "database_password_secret_arn is required when database_password_source is external_secrets. Use the Aurora module's cluster_master_user_secret_arn output, or set database_password_source = \"kubernetes_secret\"."
    }
  }
}

resource "helm_release" "temporal" {
  name             = var.name
  namespace        = var.namespace
  repository       = "https://go.temporal.io/helm-charts"
  chart            = "temporal"
  version          = var.chart_version
  create_namespace = false
  upgrade_install  = true

  # The schema job must finish before the servers can start, and the first
  # install waits for both.
  wait          = true
  wait_for_jobs = true
  timeout       = var.helm_timeout_seconds

  values = concat(
    [yamlencode(local.temporal_values)],
    var.helm_values,
  )

  depends_on = [helm_release.temporal_resources]
}
