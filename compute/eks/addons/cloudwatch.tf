################################################################################
# CloudWatch — a provider, not a mode
#
# `cloudwatch` in metrics_providers installs the amazon-cloudwatch-observability
# add-on's metrics half (Container Insights). `cloudwatch` in logs_providers
# turns on its Fluent Bit half, which ships container logs to CloudWatch Logs
# under /aws/containerinsights/<cluster>/application. Ravion's own log pipeline
# writes to /ravion/eks/<cluster> through the OpenTelemetry collector instead
# (otel_logs_collector.tf) — deliberately separate groups.
#
# Three things about the shape of this file:
#
#   1. AUTO-MONITOR IS OFF UNLESS ASKED FOR. Left at its default, the add-on's
#      webhook injects the AWS Distro agent into EVERY workload in the cluster
#      and restarts the pods to do it. That is where the wall of "AWS
#      Application Signals..." noise on ravion-test came from, and nothing in
#      the old form said it would happen. monitorAllServices is pinned false
#      here, and is only ever true when cloudwatch_application_signals_enabled
#      is set with no namespace list — an explicit, whole-cluster opt-in.
#
#   2. NEITHER HALF IS INSTALLED BY DEFAULT. The add-on appears only because
#      cloudwatch is in one of the provider lists; an instance that selects
#      neither has no CloudWatch agent, no Fluent Bit, and no webhook.
#
#   3. THE ADD-ON RUNS TWO DAEMONSETS WITH TWO SERVICE ACCOUNTS. cloudwatch-agent
#      for metrics, fluent-bit for logs; both need the same CloudWatch
#      permissions, so they share one role through two associations. Without the
#      fluent-bit association, log shipping silently falls back to the node role.
################################################################################

locals {
  # Application Signals instruments whole namespaces at a time. With a namespace
  # list the add-on's cluster-wide switch stays off and the namespaces are
  # annotated instead — see the README, and the
  # cloudwatch_application_signals_namespaces output for exactly which ones.
  cloudwatch_monitor_all_services = (
    local.cloudwatch_metrics_config.application_signals_enabled &&
    length(local.cloudwatch_metrics_config.application_signals_namespaces) == 0
  )

  # ADD-ON CONFIGURATION SCHEMA — VERIFY ON UPGRADE. The EKS API validates
  # configuration_values against the add-on's published schema and rejects
  # unknown keys, so every key below is one AWS documents:
  #
  #   agent.config.logs.metrics_collected.kubernetes.enhanced_container_insights
  #                                             — enhanced Container Insights
  #   containerLogs.enabled                     — the Fluent Bit half
  #   manager.applicationSignals.autoMonitor.monitorAllServices
  #                                             — the injection webhook
  #
  # agent.enabled is the one key this module is least sure of: it is how the
  # chart switches the metrics DaemonSet off for a logs-only install. If an
  # apply ever fails validation on it, the fix is to drop it here (the metrics
  # agent then runs alongside a logs-only selection) or to override the whole
  # document through metrics_cloudwatch.addon_configuration_values.
  cloudwatch_addon_configuration = {
    agent = {
      enabled = local.metrics_cloudwatch_enabled
      config = {
        logs = {
          metrics_collected = {
            kubernetes = {
              enhanced_container_insights = local.cloudwatch_metrics_config.enhanced_observability
            }
          }
        }
      }
    }

    containerLogs = {
      enabled = local.logs_cloudwatch_enabled
    }

    manager = {
      applicationSignals = {
        autoMonitor = {
          monitorAllServices = local.cloudwatch_monitor_all_services
        }
      }
    }
  }

  # A user-supplied document wins per top-level key: passing `agent` replaces
  # this module's whole agent subtree rather than merging into it, which is the
  # only merge rule that can be reasoned about without a deep-merge nobody can
  # read in a plan diff.
  cloudwatch_addon_configuration_values = local.cloudwatch_addon_enabled ? jsonencode(merge(
    local.cloudwatch_addon_configuration,
    local.cloudwatch_metrics_config.addon_configuration_values == null ? {} : jsondecode(local.cloudwatch_metrics_config.addon_configuration_values),
  )) : null
}

module "cloudwatch_observability_role" {
  count = local.cloudwatch_addon_enabled ? 1 : 0

  source = "../../../security/iam"

  name        = "${var.cluster_name}-cloudwatch-observability"
  description = "CloudWatch Observability add-on Pod Identity role for ${var.cluster_name}"

  custom_assume_role_policy = local.pod_identity_trust_policy

  managed_policy_arns = [
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/CloudWatchAgentServerPolicy",
  ]

  tags = local.tags
}

resource "aws_eks_pod_identity_association" "cloudwatch_agent" {
  count = local.cloudwatch_addon_enabled ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = "amazon-cloudwatch"
  service_account = "cloudwatch-agent"
  role_arn        = module.cloudwatch_observability_role[0].role_arn

  tags = local.tags
}

resource "aws_eks_pod_identity_association" "fluent_bit" {
  count = local.cloudwatch_addon_enabled ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = "amazon-cloudwatch"
  service_account = "fluent-bit"
  role_arn        = module.cloudwatch_observability_role[0].role_arn

  tags = local.tags
}

resource "aws_eks_addon" "cloudwatch_observability" {
  count = local.cloudwatch_addon_enabled ? 1 : 0

  cluster_name                = var.cluster_name
  addon_name                  = "amazon-cloudwatch-observability"
  addon_version               = local.cloudwatch_metrics_config.addon_version
  configuration_values        = local.cloudwatch_addon_configuration_values
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.tags

  depends_on = [
    aws_eks_pod_identity_association.cloudwatch_agent,
    aws_eks_pod_identity_association.fluent_bit,
  ]
}
