################################################################################
# Grafana Alloy — log collection (Helm)
#
# A DaemonSet that tails every container's stdout from /var/log/pods on its own
# node, labels it from the Kubernetes API, and pushes it to the in-cluster Loki
# (loki.tf). Alloy is Grafana's successor to Promtail, which is end-of-life.
#
# Two things about the shape of this file:
#
#   1. THE CONFIG IS THE PRODUCT. templates/alloy_config.alloy.tpl carries the
#      label contract Ravion's log views are written against — namespace, app,
#      workload, plus level as structured metadata — and the reasoning for why
#      nothing per-pod is a label. Read it before changing anything here.
#
#   2. IT READS FILES, NOT THE API. Tailing /var/log/pods keeps the log path off
#      the API server entirely, which matters because a `kubectl logs`-style
#      collector puts the read load of every container in the cluster onto the
#      control plane. The cost is a host mount and a root container, both
#      declared below.
#
# All releases set upgrade_install so an apply adopts a same-named release
# already present in the cluster instead of failing with "cannot re-use a name
# that is still in use".
################################################################################

locals {
  alloy_release_name = "ravion-alloy"

  alloy_resource_limits = merge(
    var.alloy_resources.cpu_limit == null ? {} : { cpu = var.alloy_resources.cpu_limit },
    var.alloy_resources.memory_limit == null ? {} : { memory = var.alloy_resources.memory_limit },
  )

  alloy_resource_requests = merge(
    var.alloy_resources.cpu_request == null ? {} : { cpu = var.alloy_resources.cpu_request },
    var.alloy_resources.memory_request == null ? {} : { memory = var.alloy_resources.memory_request },
  )

  alloy_resources = merge(
    length(local.alloy_resource_requests) > 0 ? { requests = local.alloy_resource_requests } : {},
    length(local.alloy_resource_limits) > 0 ? { limits = local.alloy_resource_limits } : {},
  )

  # One loki.write per selected loki-family provider. The in-cluster store comes
  # first so its receiver name stays "ravion", which the tests and every
  # debugging note about this pipeline refer to.
  alloy_destinations = concat(
    local.loki_enabled ? [{
      name         = "ravion"
      comment      = "The in-cluster store (loki.tf), queried through the EKS service proxy over SSM."
      url          = local.loki_push_url
      username     = null
      password_env = null
    }] : [],
    local.logs_grafana_cloud_enabled ? [{
      name         = "grafana_cloud"
      comment      = "Grafana Cloud Logs. Same Loki push protocol, with basic auth."
      url          = local.grafana_cloud_config.logs_url
      username     = local.grafana_cloud_config.logs_user
      password_env = "GRAFANA_CLOUD_TOKEN"
    }] : [],
  )

  # Alloy matches on a whole label, so the exclusion list is one anchored
  # alternation rather than a rule per namespace.
  alloy_namespace_exclude_regex = join("|", var.logs_excluded_namespaces)

  alloy_config = local.alloy_enabled ? templatefile("${path.module}/templates/alloy_config.alloy.tpl", {
    destinations            = local.alloy_destinations
    namespace_exclude_regex = local.alloy_namespace_exclude_regex
  }) : null

  # Vendor credentials arrive as environment variables from the Secrets the
  # External Secrets Operator materializes (observability_secrets.tf).
  alloy_extra_env = [
    for secret in local.alloy_secret_env : {
      name = secret.environment
      valueFrom = {
        secretKeyRef = {
          name = secret.name
          key  = secret.secret_key
        }
      }
    }
  ]
}

resource "helm_release" "alloy" {
  count = local.alloy_enabled ? 1 : 0

  name       = local.alloy_release_name
  namespace  = local.logs_namespace
  repository = "https://grafana.github.io/helm-charts"
  chart      = "alloy"
  version    = var.alloy_chart_version

  create_namespace = true
  upgrade_install  = true

  values = concat(
    [
      yamlencode({
        controller = {
          type = "daemonset"
        }

        alloy = {
          configMap = {
            create  = true
            content = local.alloy_config
          }

          # Single-node collection: each instance owns its own node's files, so
          # there is nothing to shard and no cluster to form.
          clustering = {
            enabled = false
          }

          # /var/log carries both the pod log files and the symlink targets
          # under /var/log/containers that they resolve through.
          mounts = {
            varlog = true
          }

          # The kubelet writes pod logs owned by root with no world read bit.
          # A collector that tails files on the host reads them as root or not
          # at all; the container is otherwise unprivileged, and this is the
          # trade for keeping log reads off the API server.
          securityContext = {
            runAsUser  = 0
            runAsGroup = 0
          }

          resources = local.alloy_resources

          # Vendor tokens, by reference. CHART VALUE: grafana/alloy exposes
          # alloy.extraEnv as a list of core v1 EnvVar objects.
          extraEnv = local.alloy_extra_env

          # Nothing about this cluster is Grafana Labs' business.
          enableReporting = false
        }

        # The chart's default rules already cover discovery.kubernetes.
        rbac = {
          create = true
        }

        serviceAccount = {
          create = true
        }

        # Nothing scrapes or calls Alloy: it discovers, reads and pushes. The
        # UI on 12345 stays reachable through a port-forward for debugging.
        service = {
          enabled = false
        }
      }),
    ],
    var.alloy_helm_values,
  )

  # Pushing into a Loki that does not exist yet is a retry loop and a page of
  # errors in the first minutes of a cluster's life; a missing credential Secret
  # is a pod that never starts.
  depends_on = [
    helm_release.loki,
    helm_release.observability_secrets,
  ]

  lifecycle {
    precondition {
      condition     = !local.logs_grafana_cloud_enabled || (local.grafana_cloud_config.logs_url != null && local.grafana_cloud_config.logs_user != null && local.grafana_cloud_config.token_secret_arn != null)
      error_message = "grafana_cloud is in logs_providers but its push URL, user id, or token secret ARN is missing. All three are required: Grafana Cloud's Loki endpoint authenticates every write with basic auth, so a partial configuration is a collector that starts and then fails every push."
    }
  }
}
