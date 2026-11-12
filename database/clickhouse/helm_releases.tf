################################################################################
# Helm releases
#
# Three releases, applied in order:
#
#   1. <name>-secrets   The External Secrets resources that copy the user
#                       credentials into Kubernetes Secrets (local chart).
#   2. <name>-operator  The Altinity clickhouse-operator, watching only this
#                       namespace (upstream chart, pinned).
#   3. <name>           ClickHouse Keeper, the ClickHouse installation, the
#                       backup schedule and the rest (local chart).
#
# The operator reads its own ClickHouse credentials once, at startup, so its
# container also references that Secret: Kubernetes holds the pod until the
# External Secrets Operator has written it, and the operator never starts
# without credentials.
################################################################################

locals {
  secrets_chart = "${path.module}/charts/clickhouse-secrets"
  cluster_chart = "${path.module}/charts/clickhouse-cluster"

  # Changing it restarts the operator and the ClickHouse pods so they read the
  # new passwords, and makes External Secrets refresh at once.
  password_annotation = { "clickhouse.ravion.com/password-version" = tostring(var.password_version) }

  tolerations = var.dedicated_node_pool.enabled ? [{
    key      = "clickhouse.ravion.com/dedicated"
    operator = "Equal"
    value    = var.name
    effect   = "NoSchedule"
  }] : []
}

resource "helm_release" "secrets" {
  name             = "${var.name}-secrets"
  namespace        = var.namespace
  create_namespace = var.namespace_creation_enabled
  chart            = local.secrets_chart
  # Pinned so a Chart.yaml bump shows in the plan.
  version         = yamldecode(file("${path.module}/charts/clickhouse-secrets/Chart.yaml")).version
  upgrade_install = true
  timeout         = var.helm_timeout_seconds

  values = [yamlencode({
    region          = local.region
    refreshInterval = var.external_secrets.refresh_interval
    passwordVersion = tostring(var.password_version)
    store = {
      create = var.external_secrets.cluster_secret_store_name == null
      name   = coalesce(var.external_secrets.cluster_secret_store_name, "${var.name}-aws-secrets-manager")
      kind   = var.external_secrets.cluster_secret_store_name == null ? "SecretStore" : "ClusterSecretStore"
    }
    secrets = [
      for key, user in local.users : {
        name      = user.secret
        remoteKey = aws_secretsmanager_secret.user[key].name
      }
    ]
  })]

  depends_on = [aws_secretsmanager_secret_version.user]
}

resource "helm_release" "operator" {
  name            = local.operator_fullname
  namespace       = var.namespace
  repository      = "https://helm.altinity.com"
  chart           = "altinity-clickhouse-operator"
  version         = var.operator_chart_version
  upgrade_install = true
  timeout         = var.helm_timeout_seconds

  values = [yamlencode({
    fullnameOverride = local.operator_fullname

    # Watch only this namespace, with Roles rather than ClusterRoles.
    watchNamespaces = [var.namespace]
    rbac = {
      create          = true
      namespaceScoped = true
    }

    crdHook = {
      enabled = var.operator_crds_management_enabled
    }

    # The credentials Secret comes from External Secrets (release 1).
    secret = {
      create = false
    }

    operator = {
      resources = {
        requests = {
          cpu    = var.operator_resources.cpu_request
          memory = var.operator_resources.memory_request
        }
        limits = {
          memory = var.operator_resources.memory_limit
        }
      }
      env = [{
        name = "CLICKHOUSE_OPERATOR_CREDENTIALS_PRESENT"
        valueFrom = {
          secretKeyRef = {
            name = local.operator_fullname
            key  = "username"
          }
        }
      }]
    }

    # ClickHouse and Keeper serve their own Prometheus endpoints (see the
    # cluster chart), so the operator's polling exporter would only duplicate
    # them. The operator's own metrics stay on 9999.
    metrics = {
      enabled = false
    }
    podAnnotations = merge(local.password_annotation, {
      "prometheus.io/scrape" = "true"
      "prometheus.io/port"   = "9999"
      "prometheus.io/path"   = "/metrics"
    })
    serviceMonitor = {
      enabled = false
    }
  })]

  depends_on = [helm_release.secrets]
}

resource "helm_release" "cluster" {
  name      = var.name
  namespace = var.namespace
  chart     = local.cluster_chart
  # Pinned so a Chart.yaml bump shows in the plan.
  version         = yamldecode(file("${path.module}/charts/clickhouse-cluster/Chart.yaml")).version
  upgrade_install = true
  timeout         = var.helm_timeout_seconds

  values = [yamlencode({
    name        = var.name
    clusterName = local.cluster_layout_name
    region      = local.region

    passwordAnnotations = local.password_annotation
    users = {
      admin  = local.users.admin
      writer = local.users.writer
      reader = local.users.reader
    }
    operatorFullname = local.operator_fullname

    serviceAccount = {
      name = local.service_account_name
    }

    clickhouse = {
      image    = var.clickhouse_image
      shards   = var.shard_count
      replicas = var.replica_count
      resources = {
        requests = {
          cpu    = var.clickhouse_resources.cpu_request
          memory = var.clickhouse_resources.memory_request
        }
        limits = merge(
          var.clickhouse_resources.memory_limit == null ? {} : { memory = var.clickhouse_resources.memory_limit },
          var.clickhouse_resources.cpu_limit == null ? {} : { cpu = var.clickhouse_resources.cpu_limit },
        )
      }
      volumeSize = var.clickhouse_volume_size
      settings   = var.clickhouse_settings
    }

    keeper = {
      image    = var.keeper_image
      replicas = var.keeper_replica_count
      resources = {
        requests = {
          cpu    = var.keeper_resources.cpu_request
          memory = var.keeper_resources.memory_request
        }
        limits = merge(
          var.keeper_resources.memory_limit == null ? {} : { memory = var.keeper_resources.memory_limit },
          var.keeper_resources.cpu_limit == null ? {} : { cpu = var.keeper_resources.cpu_limit },
        )
      }
      volumeSize = var.keeper_volume_size
    }

    storage = {
      storageClassName = var.storage_class_name
      reclaimPolicy    = var.volume_reclaim_policy
    }

    placement = {
      zoneSpread = var.zone_spread
      priorityClass = {
        create = var.priority_class.enabled
        name   = "${var.namespace}-${var.name}-clickhouse"
        value  = var.priority_class.value
      }
      nodePool = {
        create             = var.dedicated_node_pool.enabled
        name               = "${var.namespace}-${var.name}-clickhouse"
        nodeClassName      = var.dedicated_node_pool.node_class_name
        capacityTypes      = var.dedicated_node_pool.capacity_types
        instanceCategories = var.dedicated_node_pool.instance_categories
        architectures      = var.dedicated_node_pool.architectures
        cpuLimit           = var.dedicated_node_pool.cpu_limit
      }
      tolerations = local.tolerations
    }

    database = {
      name   = var.database_name == null ? "" : var.database_name
      engine = var.database_engine
    }

    reader = {
      maxExecutionTime     = var.reader_limits.max_execution_time_seconds
      maxMemoryUsage       = var.reader_limits.max_memory_usage_mib * 1048576
      maxConcurrentQueries = var.reader_limits.max_concurrent_queries
    }

    s3 = {
      bucket = local.s3_enabled ? local.s3_bucket_name : ""
      region = local.s3_enabled ? local.s3_bucket_region : ""
    }

    coldStorage = {
      enabled   = var.cold_storage_enabled
      cacheSize = var.cold_storage_cache_size
    }

    backup = {
      enabled        = var.backup_enabled
      schedule       = var.backup_schedule
      retentionCount = var.backup_retention_count
      image          = var.backup_image
      jobImage       = var.backup_job_image
      resources = {
        requests = {
          cpu    = var.backup_resources.cpu_request
          memory = var.backup_resources.memory_request
        }
        limits = {
          memory = var.backup_resources.memory_limit
        }
      }
    }

    metrics = {
      podMonitors = {
        enabled = var.metrics_pod_monitors_enabled
        labels  = var.metrics_pod_monitor_labels
      }
      otlp = {
        endpoint = var.metrics_otlp_endpoint == null ? "" : var.metrics_otlp_endpoint
        interval = var.metrics_otlp_interval
        image    = var.metrics_otlp_collector_image
      }
    }

    networkPolicy = {
      enabled           = var.network_policy_enabled
      allowedNamespaces = var.network_policy_allowed_namespaces
    }
  })]

  depends_on = [
    helm_release.operator,
    aws_eks_pod_identity_association.clickhouse,
    aws_iam_role_policy.clickhouse_s3,
  ]
}
