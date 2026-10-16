################################################################################
# Add-on resilience
#
# Placement (addon_placement.tf) keeps the add-ons off Spot. This keeps them
# running once placed. In ravion-prod the Prometheus server, which requested no
# memory, was packed onto 2-4 GiB nodes it then exhausted, OOM-killed and
# evicted for hours; KEDA lost its metrics and every deploy that waited on a
# ScaledObject failed. Each add-on now gets:
#
#   1. A priority class above applications: system-cluster-critical for
#      controllers and stores, system-node-critical for per-node agents.
#      Under pressure the kubelet evicts, and the scheduler preempts,
#      applications first.
#   2. Two replicas behind a minAvailable=1 budget, preferring distinct nodes,
#      for every controller that can run more than one (KEDA, cert-manager,
#      External Secrets, Thanos Query and Store). A drain or reclaim then
#      never removes the only copy.
#   3. karpenter.sh/do-not-disrupt on single-replica stores (Prometheus, Loki,
#      Tempo, the Thanos compactor), which cannot be budgeted without blocking
#      every drain, so consolidation never moves them mid-write.
#   4. Requests that match what each component uses, so the node it lands on
#      can hold it.
#
# Values are delivered as their own document after the placement and ahead of
# each release's caller Helm values, so a caller document can still replace any
# of it.
################################################################################

locals {
  addon_critical_priority = "system-cluster-critical"
  node_critical_priority  = "system-node-critical"

  addon_do_not_disrupt = { "karpenter.sh/do-not-disrupt" = "true" }

  addon_budget = { minAvailable = 1 }

  # The stores (Prometheus, Loki, Tempo, the Thanos compactor) hold data and
  # take minutes to restart, so they get nodes of their own: a dedicated
  # Karpenter NodePool of On-Demand nodes with room for them, tainted so
  # applications never compete with them for memory. It needs the default
  # NodePool's EC2NodeClass, and placement on to deliver it.
  addon_stateful_pool_name    = "addon-stateful"
  addon_stateful_taint_key    = "ravion.com/addon-stateful"
  addon_stateful_pool_enabled = var.addon_stateful_node_pool_enabled && var.addon_placement_enabled && var.karpenter_enabled && var.karpenter_default_node_pool_creation_enabled

  addon_stateful_placement = {
    affinity = {
      nodeAffinity = {
        requiredDuringSchedulingIgnoredDuringExecution = {
          nodeSelectorTerms = [{ matchExpressions = [{ key = "karpenter.sh/nodepool", operator = "In", values = [local.addon_stateful_pool_name] }] }]
        }
      }
    }
    tolerations = concat(
      [{ key = local.addon_stateful_taint_key, operator = "Exists", effect = "NoSchedule" }],
      local.addon_tolerations,
    )
  }

  # What a store gets: its own nodes when the pool exists, otherwise the shared
  # add-on placement. Round-tripped through JSON because the two documents
  # differ in shape, which a conditional cannot return.
  addon_store_placement = jsondecode(local.addon_stateful_pool_enabled ? jsonencode(local.addon_stateful_placement) : jsonencode(local.addon_pod_placement))

  # Soft: a cluster with one eligible node still schedules both replicas.
  # pod-template-hash keeps a rollout's new pods from counting the old ones.
  addon_spread = {
    maxSkew           = 1
    topologyKey       = "kubernetes.io/hostname"
    whenUnsatisfiable = "ScheduleAnyway"
    matchLabelKeys    = ["pod-template-hash"]
  }

  # Spread constraints select a component's pods by the two standard labels
  # every chart below sets on its pod templates.
  addon_spread_for = {
    for component, labels in {
      keda_operator                    = { name = "keda-operator", instance = "keda" }
      keda_metrics_apiserver           = { name = "keda-operator-metrics-apiserver", instance = "keda" }
      keda_webhooks                    = { name = "keda-admission-webhooks", instance = "keda" }
      cert_manager                     = { name = "cert-manager", instance = "cert-manager" }
      cert_manager_webhook             = { name = "webhook", instance = "cert-manager" }
      cert_manager_cainjector          = { name = "cainjector", instance = "cert-manager" }
      external_secrets                 = { name = "external-secrets", instance = "external-secrets" }
      external_secrets_webhook         = { name = "external-secrets-webhook", instance = "external-secrets" }
      external_secrets_cert_controller = { name = "external-secrets-cert-controller", instance = "external-secrets" }
      } : component => [merge(local.addon_spread, {
        labelSelector = { matchLabels = { "app.kubernetes.io/name" = labels.name, "app.kubernetes.io/instance" = labels.instance } }
    })]
  }

  # Controllers that leader-elect: a second replica is a hot standby.
  addon_controller_resources = {
    requests = { cpu = "50m", memory = "128Mi" }
    limits   = { memory = "512Mi" }
  }
  addon_webhook_resources = {
    requests = { cpu = "20m", memory = "64Mi" }
    limits   = { memory = "256Mi" }
  }

  keda_resilience_values = var.addon_resilience_enabled ? [yamlencode({
    priorityClassName = local.addon_critical_priority
    # The metrics apiserver backs the external.metrics.k8s.io APIService; while
    # it is down, API discovery fails for every client, Helm included.
    operator      = { replicaCount = 2 }
    metricsServer = { replicaCount = 2 }
    webhooks      = { replicaCount = 2 }
    podDisruptionBudget = {
      operator     = local.addon_budget
      metricServer = local.addon_budget
      webhooks     = local.addon_budget
    }
    topologySpreadConstraints = {
      operator      = local.addon_spread_for.keda_operator
      metricsServer = local.addon_spread_for.keda_metrics_apiserver
      webhooks      = local.addon_spread_for.keda_webhooks
    }
  })] : []

  cert_manager_resilience_values = var.addon_resilience_enabled ? [yamlencode({
    global                    = { priorityClassName = local.addon_critical_priority }
    replicaCount              = 2
    podDisruptionBudget       = merge({ enabled = true }, local.addon_budget)
    resources                 = local.addon_controller_resources
    topologySpreadConstraints = local.addon_spread_for.cert_manager
    webhook = {
      replicaCount              = 2
      podDisruptionBudget       = merge({ enabled = true }, local.addon_budget)
      resources                 = local.addon_webhook_resources
      topologySpreadConstraints = local.addon_spread_for.cert_manager_webhook
    }
    cainjector = {
      replicaCount              = 2
      podDisruptionBudget       = merge({ enabled = true }, local.addon_budget)
      resources                 = local.addon_controller_resources
      topologySpreadConstraints = local.addon_spread_for.cert_manager_cainjector
    }
  })] : []

  external_secrets_resilience_values = var.addon_resilience_enabled ? [yamlencode({
    # Without leader election two controllers would both reconcile every
    # ExternalSecret.
    leaderElect               = true
    replicaCount              = 2
    priorityClassName         = local.addon_critical_priority
    podDisruptionBudget       = merge({ enabled = true }, local.addon_budget)
    resources                 = local.addon_controller_resources
    topologySpreadConstraints = local.addon_spread_for.external_secrets
    webhook = {
      replicaCount              = 2
      priorityClassName         = local.addon_critical_priority
      podDisruptionBudget       = merge({ enabled = true }, local.addon_budget)
      resources                 = local.addon_webhook_resources
      topologySpreadConstraints = local.addon_spread_for.external_secrets_webhook
    }
    certController = {
      replicaCount              = 2
      priorityClassName         = local.addon_critical_priority
      podDisruptionBudget       = merge({ enabled = true }, local.addon_budget)
      resources                 = local.addon_controller_resources
      topologySpreadConstraints = local.addon_spread_for.external_secrets_cert_controller
    }
  })] : []

  # The chart already runs two replicas at system-cluster-critical with
  # anti-affinity; its webhook gates every Service and Ingress, so a drain
  # must always leave one.
  lb_controller_resilience_values = var.addon_resilience_enabled ? [yamlencode({
    podDisruptionBudget = { maxUnavailable = 1 }
    resources = {
      requests = { cpu = "100m", memory = "256Mi" }
      limits   = { memory = "512Mi" }
    }
  })] : []

  # One replica on purpose (a second would double every series); its memory
  # grows with the number of objects in the cluster.
  kube_state_metrics_resilience_values = var.addon_resilience_enabled ? [yamlencode({
    priorityClassName = local.addon_critical_priority
    resources = {
      requests = { cpu = "50m", memory = "128Mi" }
      limits   = { memory = "512Mi" }
    }
  })] : []

  # The collectors stay single replicas: two writers of the same series into
  # Prometheus' remote-write receiver would produce out-of-order samples.
  collector_resilience_values = var.addon_resilience_enabled ? [yamlencode({
    priorityClassName = local.addon_critical_priority
  })] : []

  node_agent_resilience_values = var.addon_resilience_enabled ? [yamlencode({
    priorityClassName = local.node_critical_priority
    # A node the agent skips is a node whose logs never leave it.
    tolerations = [{ operator = "Exists" }]
  })] : []

  alloy_resilience_values = var.addon_resilience_enabled ? [yamlencode({
    controller = { priorityClassName = local.node_critical_priority }
  })] : []

  prometheus_resilience_values = var.addon_resilience_enabled ? [yamlencode({
    server = {
      resources         = var.prometheus_resources
      priorityClassName = local.addon_critical_priority
      podAnnotations    = local.addon_do_not_disrupt
      # Replaying a multi-GiB WAL can take minutes; until it finishes the
      # liveness probe would restart the server and start the replay over.
      startupProbe = { enabled = true, periodSeconds = 10, failureThreshold = 60, timeoutSeconds = 10 }
    }
  })] : []

  loki_resilience_values = var.addon_resilience_enabled ? [yamlencode({
    singleBinary = {
      priorityClassName = local.addon_critical_priority
      podAnnotations    = local.addon_do_not_disrupt
    }
  })] : []

  tempo_resilience_values = var.addon_resilience_enabled ? [yamlencode({
    priorityClassName = local.addon_critical_priority
    podAnnotations    = local.addon_do_not_disrupt
  })] : []

  grafana_resilience_values = var.addon_resilience_enabled ? [yamlencode({
    priorityClassName = local.addon_critical_priority
    resources = {
      requests = { cpu = "100m", memory = "256Mi" }
      limits   = { memory = "512Mi" }
    }
  })] : []

  # Query is on KEDA's path to its metrics and Store serves history: both are
  # stateless and run two. The compactor must stay a singleton.
  thanos_resilience_values = var.addon_resilience_enabled ? [yamlencode({
    priorityClassName = local.addon_critical_priority
    query             = { replicas = 2 }
    store             = { replicas = 2 }
    compactor         = { podAnnotations = local.addon_do_not_disrupt }
  })] : []

  # Karpenter's chart already runs it at system-cluster-critical behind a
  # budget, off Karpenter nodes.
  karpenter_resilience_values = var.addon_resilience_enabled ? [yamlencode({
    controller = {
      resources = {
        requests = { cpu = "250m", memory = "512Mi" }
        limits   = { memory = "1Gi" }
      }
    }
    # Replaces a node that stays NotReady, so it cannot hold a store's EBS
    # volume hostage the way ravion-prod's did. Alpha in Karpenter 1.x.
    settings = { featureGates = { nodeRepair = true } }
  })] : []

  # Four fifths of a Gi-sized volume, in the GB unit Prometheus reads. A size
  # in any other unit leaves retention bounded by time alone.
  prometheus_retention_size = can(regex("^([0-9]+)Gi$", local.prometheus_config.storage_size)) ? "${floor(tonumber(regex("^([0-9]+)Gi$", local.prometheus_config.storage_size)[0]) * 4 / 5)}GB" : ""
}
