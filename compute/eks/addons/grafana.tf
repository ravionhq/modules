################################################################################
# In-cluster Grafana (optional)
#
# Grafana running beside Loki, preprovisioned with both Ravion datasources:
# Amazon Managed Prometheus over SigV4, and the in-cluster Loki over plain HTTP.
#
# WHY IN-CLUSTER AND NOT AMAZON MANAGED GRAFANA. AMG can query AMP perfectly
# well — grafana_role.tf exists for exactly that — but it runs in an AWS-managed
# VPC and cannot reach a ClusterIP Service. Loki is deliberately not exposed
# outside the cluster, so "the logs, in Grafana" is only answerable by a Grafana
# that is inside it. Customers who only want metrics dashboards should prefer
# AMG and leave this off.
#
# No ingress and no Service type beyond ClusterIP: reaching it is a
# port-forward, or whatever the operator adds through grafana_helm_values. A
# module that quietly published a Grafana with a default admin password to the
# internet would be a bug, not a convenience.
#
# All releases set upgrade_install so an apply adopts a same-named release
# already present in the cluster instead of failing with "cannot re-use a name
# that is still in use".
################################################################################

locals {
  grafana_release_name = "ravion-grafana"

  # Only the datasources whose backing pipeline is actually installed. Grafana
  # renders a datasource it cannot reach as a permanently failing panel, which
  # is worse than an absent one.
  grafana_datasources = concat(
    local.amp_enabled ? [
      {
        name      = "Ravion Metrics (AMP)"
        uid       = "ravion-amp"
        type      = "prometheus"
        access    = "proxy"
        url       = local.amp_query_endpoint
        isDefault = !local.loki_enabled
        jsonData = {
          httpMethod = "POST"
          # Signed with whatever the AWS SDK default chain resolves, which the
          # Pod Identity association below populates — no keys, no assumed role.
          sigV4Auth     = true
          sigV4AuthType = "default"
          sigV4Region   = local.amp_region
        }
      },
    ] : [],
    local.prometheus_enabled ? [
      {
        name      = "Ravion Metrics (in-cluster Prometheus)"
        uid       = "ravion-prometheus"
        type      = "prometheus"
        access    = "proxy"
        url       = local.prometheus_endpoint
        isDefault = !local.amp_enabled && !local.loki_enabled
        jsonData = {
          httpMethod = "POST"
        }
      },
    ] : [],
    local.loki_enabled ? [
      {
        name      = "Ravion Logs (Loki)"
        uid       = "ravion-loki"
        type      = "loki"
        access    = "proxy"
        url       = local.loki_endpoint
        isDefault = true
      },
    ] : [],
  )
}

################################################################################
# Grafana's AMP read identity
################################################################################

data "aws_iam_policy_document" "grafana_workspace_read" {
  count = var.grafana_enabled && local.amp_enabled ? 1 : 0

  statement {
    sid    = "QueryPrometheusWorkspace"
    effect = "Allow"
    actions = [
      "aps:QueryMetrics",
      "aps:GetSeries",
      "aps:GetLabels",
      "aps:GetMetricMetadata",
    ]
    resources = [local.amp_workspace_arn]
  }
}

module "grafana_workspace_read_role" {
  count = var.grafana_enabled && local.amp_enabled ? 1 : 0

  source = "../../../security/iam"

  name        = "${var.cluster_name}-grafana-amp"
  description = "In-cluster Grafana Pod Identity role for querying the AMP workspace of ${var.cluster_name}"

  custom_assume_role_policy = local.pod_identity_trust_policy

  inline_policies = {
    "workspace-read" = data.aws_iam_policy_document.grafana_workspace_read[0].json
  }

  tags = local.tags
}

resource "aws_eks_pod_identity_association" "grafana" {
  count = var.grafana_enabled && local.amp_enabled ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = local.grafana_namespace
  service_account = var.grafana_service_account
  role_arn        = module.grafana_workspace_read_role[0].role_arn

  tags = local.tags
}

################################################################################
# Grafana
################################################################################

resource "helm_release" "grafana" {
  count = var.grafana_enabled ? 1 : 0

  name      = local.grafana_release_name
  namespace = local.grafana_namespace
  # grafana/grafana on grafana.github.io was deprecated and handed to
  # grafana-community in January 2026; the old copy still resolves and still
  # installs, but it stopped receiving updates, so pinning it would pin Grafana
  # itself. Loki and Alloy are unaffected — those charts did not move.
  repository = "https://grafana-community.github.io/helm-charts"
  chart      = "grafana"
  version    = var.grafana_chart_version

  create_namespace = true
  upgrade_install  = true

  values = concat(
    [
      yamlencode({
        fullnameOverride = local.grafana_release_name

        # Must match the Pod Identity association above, or the SigV4
        # datasource signs with the node role and every query is denied.
        serviceAccount = {
          create = true
          name   = var.grafana_service_account
        }

        # SigV4 is off in Grafana by default and a datasource that asks for it
        # without this simply fails to authenticate, with no hint as to why.
        "grafana.ini" = {
          auth = {
            sigv4_auth_enabled = true
          }
        }

        datasources = {
          "datasources.yaml" = {
            apiVersion  = 1
            datasources = local.grafana_datasources
          }
        }
      }),
    ],
    var.grafana_helm_values,
  )

  depends_on = [
    helm_release.lb_controller,
    aws_eks_pod_identity_association.grafana,
    helm_release.loki,
  ]

  lifecycle {
    precondition {
      condition     = local.metrics_on || local.logs_on
      error_message = "grafana_enabled is true but both logs_providers and metrics_providers are empty. Grafana would install with no datasources at all — select the provider you want to look at, or leave Grafana off."
    }
  }
}
