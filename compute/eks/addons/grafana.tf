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
# The Service is ClusterIP only: reaching Grafana is a port-forward unless
# grafana_access serves it on a shared ALB or through an Ingress
# (grafana_access.tf). A module that quietly published a Grafana with a
# default admin password to the internet would be a bug, not a convenience.
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
    local.tempo_enabled ? [
      merge(
        {
          name      = "Ravion Traces (Tempo)"
          uid       = "ravion-tempo"
          type      = "tempo"
          access    = "proxy"
          url       = local.tempo_endpoint
          isDefault = !local.amp_enabled && !local.prometheus_enabled && !local.loki_enabled
        },
        # The metrics generator's service graphs, drawn from the Prometheus it
        # writes to.
        {
          for key, value in {
            jsonData = {
              serviceMap = {
                datasourceUid = local.tempo_generator_to_amp ? "ravion-amp" : "ravion-prometheus"
              }
            }
          } : key => value if local.tempo_generator_enabled
        },
      ),
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

  name        = "${local.name}-grafana-amp"
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
      yamlencode(merge({
        fullnameOverride = local.grafana_release_name

        # Must match the Pod Identity association above, or the SigV4
        # datasource signs with the node role and every query is denied.
        serviceAccount = {
          create = true
          name   = var.grafana_service_account
        }

        # SigV4 is off in Grafana by default and a datasource that asks for it
        # without this simply fails to authenticate, with no hint as to why.
        # Sign-in and load balancer access settings come from grafana_auth.tf.
        "grafana.ini" = local.grafana_ini
        envValueFrom  = local.grafana_env_value_from

        datasources = {
          "datasources.yaml" = {
            apiVersion  = 1
            datasources = local.grafana_datasources
          }
        }
      }, local.grafana_ingress_values)),
    ],
    var.grafana_helm_values,
  )

  depends_on = [
    helm_release.lb_controller,
    aws_eks_pod_identity_association.grafana,
    helm_release.loki,
    helm_release.thanos,
    helm_release.tempo,
    # The sign-in providers' client secrets must exist before its pod starts.
    helm_release.observability_secrets,
  ]

  lifecycle {
    precondition {
      condition     = local.metrics_on || local.logs_on || local.tempo_enabled
      error_message = "grafana_enabled is true but logs_providers and metrics_providers are empty and tempo is not a traces provider. Grafana would install with no datasources at all — select the provider you want to look at, or leave Grafana off."
    }

    precondition {
      condition     = !local.grafana_access_enabled || local.grafana_hostname != ""
      error_message = "grafana_access is enabled without a hostname. Grafana is served at that hostname, and OAuth providers redirect back to it."
    }

    precondition {
      condition     = var.grafana_auth.login_form_enabled || length(local.grafana_auth_entries) > 0
      error_message = "Grafana would have no way to sign in: grafana_auth.login_form_enabled is false and grafana_auth_providers is empty."
    }

    precondition {
      condition     = length(local.grafana_auth_without_client) == 0
      error_message = "Each Grafana sign-in provider needs a client ID (client_id, or client_id_arn) and the Secrets Manager ARN of its client secret: ${join(", ", local.grafana_auth_without_client)}."
    }

    precondition {
      condition     = length(local.grafana_secret_env_overlapping) == 0
      error_message = "grafana_secret_env sets env vars the module sets for the sign-in providers' clients: ${join(", ", local.grafana_secret_env_overlapping)}. Set those through client_id, client_id_arn and client_secret_arn."
    }

    precondition {
      condition     = length(local.grafana_auth_client_id_twice) == 0
      error_message = "These Grafana sign-in providers set both client_id and client_id_arn: ${join(", ", local.grafana_auth_client_id_twice)}. Set one."
    }

    precondition {
      condition     = length(local.grafana_auth_unrestricted) == 0
      error_message = "Anyone with an account at these providers could sign in to Grafana: ${join(", ", local.grafana_auth_unrestricted)}. Set google allowed_domains or allowed_groups; github allowed_organizations, team_ids or allowed_domains; gitlab allowed_groups or allowed_domains (or a self-managed url)."
    }

    precondition {
      condition     = length(local.grafana_auth_without_endpoint) == 0
      error_message = "These Grafana sign-in providers are missing where to sign in: ${join(", ", local.grafana_auth_without_endpoint)}. azuread needs tenant_id, okta needs url, and generic_oauth needs auth_url and token_url."
    }

    precondition {
      condition     = length(local.grafana_auth_google_groups_without_scope) == 0
      error_message = "Google sign-in uses Workspace groups (allowed_groups, or groups in role_attribute_path) but its scopes leave out ${local.grafana_google_groups_scope}. Grafana reads no groups without it. Set scopes to \"openid email profile ${local.grafana_google_groups_scope}\", and enable the Cloud Identity API in the OAuth client's Google Cloud project."
    }

    precondition {
      condition     = length(local.grafana_auth_settings_overlapping) == 0
      error_message = "A Grafana sign-in provider's settings set a key the module manages: ${join(", ", local.grafana_auth_settings_overlapping)}. settings is for the other keys of [auth.<provider>]. Set client_id, the restrictions, endpoints, scopes, name and role_attribute_path as their own fields, and the client secret as client_secret_arn."
    }
  }
}
