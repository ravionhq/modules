################################################################################
# Local Values
################################################################################

locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "compute/eks/addons"
  }

  tags = merge(local.default_tags, var.tags)

  # Shared trust policy for EKS Pod Identity roles: the role is bound to a
  # service account at runtime via the Pod Identity Agent.
  pod_identity_trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  # Ravion's in-cluster components share one namespace by default: Ravion Operator, both
  # collectors, kube-state-metrics, Loki, Prometheus, the materialized vendor
  # credentials, and Grafana. Each has its own override so a cluster that wants
  # them apart can have that, but the default keeps them together — one
  # namespace to grant Ravion Operator observation on, and one place to look when the
  # pipeline is the thing that is wrong.
  #
  # observability_namespace deliberately defaults to Ravion Operator's namespace rather
  # than to a namespace of its own: moving Loki would change the Service URL the
  # control plane defaults to, for no gain.
  observability_namespace = coalesce(var.observability_namespace, var.ravion_operator_namespace)
  metrics_namespace       = coalesce(var.metrics_namespace, local.observability_namespace)
  logs_namespace          = coalesce(var.logs_namespace, local.observability_namespace)
  grafana_namespace       = coalesce(var.grafana_namespace, local.observability_namespace)
}

################################################################################
# Curated metric allow-list
#
# The load-bearing part of the metrics pipeline. Kubernetes exposes tens of
# thousands of series per cluster; AMP bills per sample ingested, so the
# collector keeps a named set and drops everything else with a `keep` action in
# metric_relabel_configs — before the samples enter collector memory, not after.
#
# One list per scrape job, because a family only ever comes from one of them.
# Each is concatenated with `up` (scrape health is the first debugging
# question) and with var.metrics_additional_allowlist, then joined into a single
# alternation. Prometheus anchors relabel regexes at both ends, so each branch
# must match a whole metric name: "my_app_.*", never ".*my_app.*".
################################################################################

locals {
  # kubelet /metrics/cadvisor — per-container resource usage.
  metrics_cadvisor_allowlist = [
    "container_cpu_usage_seconds_total",
    "container_cpu_cfs_throttled_periods_total",
    "container_cpu_cfs_periods_total",
    "container_memory_working_set_bytes",
    "container_memory_rss",
    "container_network_receive_bytes_total",
    "container_network_transmit_bytes_total",
    "container_oom_events_total",
  ]

  # kube-state-metrics — desired vs. actual state of the objects Ravion renders.
  metrics_kube_state_allowlist = [
    "kube_pod_info",
    "kube_pod_owner",
    "kube_pod_status_phase",
    "kube_pod_status_ready",
    "kube_pod_container_status_restarts_total",
    "kube_pod_container_status_waiting_reason",
    "kube_pod_container_status_last_terminated_reason",
    "kube_pod_container_resource_requests",
    "kube_pod_container_resource_limits",
    "kube_deployment_spec_replicas",
    "kube_deployment_status_replicas_available",
    "kube_deployment_status_replicas_unavailable",
    "kube_statefulset_replicas",
    "kube_statefulset_status_replicas_ready",
    "kube_daemonset_status_desired_number_scheduled",
    "kube_daemonset_status_number_ready",
    "kube_job_status_failed",
    "kube_job_status_succeeded",
    "kube_horizontalpodautoscaler_spec_max_replicas",
    "kube_horizontalpodautoscaler_status_current_replicas",
    "kube_horizontalpodautoscaler_status_desired_replicas",
    "kube_node_status_condition",
    "kube_node_status_allocatable",
    "kube_node_status_capacity",
  ]

  # kubelet /metrics/resource — node headline usage, which is what makes a
  # node-exporter DaemonSet unnecessary in this pipeline.
  metrics_kubelet_resource_allowlist = [
    "node_cpu_usage_seconds_total",
    "node_memory_working_set_bytes",
  ]

  metrics_cadvisor_keep_regex = join("|", concat(
    local.metrics_cadvisor_allowlist,
    ["up"],
    var.metrics_additional_allowlist,
  ))

  metrics_kube_state_keep_regex = join("|", concat(
    local.metrics_kube_state_allowlist,
    ["up"],
    var.metrics_additional_allowlist,
  ))

  metrics_kubelet_resource_keep_regex = join("|", concat(
    local.metrics_kubelet_resource_allowlist,
    ["up"],
    var.metrics_additional_allowlist,
  ))
}
