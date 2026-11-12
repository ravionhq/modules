locals {
  database_engine = data.aws_rds_cluster.database.engine
  database_host   = data.aws_rds_cluster.database.endpoint
  database_port   = data.aws_rds_cluster.database.port
  database_user   = coalesce(var.database_username, data.aws_rds_cluster.database.master_username)

  database_secret_name     = coalesce(var.database_password_kubernetes_secret_name, "${var.name}-db")
  database_ca_config_map   = "${var.name}-rds-ca"
  database_ca_mount_path   = "/etc/temporal/rds-ca"
  database_external_secret = var.database_password_source == "external_secrets"

  # Services are prefixed with the release name (fullnameOverride below).
  frontend_host          = "${var.name}-frontend.${var.namespace}.svc"
  frontend_port          = 7233
  frontend_http_port     = 7243
  web_host               = "${var.name}-web.${var.namespace}.svc"
  internode_server_name  = "${var.name}-internode.${var.namespace}.svc"
  tls_ca_secret_name     = "${var.name}-ca"
  tls_frontend_secret    = "${var.name}-frontend-tls"
  tls_internode_secret   = "${var.name}-internode-tls"
  resources_release_name = "${var.name}-resources"

  priority_class_name = var.priority_class_creation_enabled ? coalesce(var.priority_class_name, "${var.name}-critical") : var.priority_class_name
  node_pool_name      = var.name
  node_pool_taint_key = "ravion.com/dedicated"

  web_ingress_alb             = var.web_ingress_enabled && var.web_ingress_class_name == "alb"
  web_ingress_vpc_cidr_needed = var.web_enabled && var.web_ingress_enabled && var.network_policy_enabled
  network_policy_web_cidrs = distinct(concat(
    var.network_policy_web_client_cidrs,
    local.web_ingress_vpc_cidr_needed ? [data.aws_vpc.cluster[0].cidr_block] : [],
  ))

  metrics_otlp_enabled = var.metrics_otlp_endpoint != null && var.metrics_otlp_endpoint != ""

  # Placement shared by every Temporal pod.
  node_selector = var.node_pool_creation_enabled ? { "karpenter.sh/nodepool" = local.node_pool_name } : {}
  tolerations = var.node_pool_creation_enabled ? [{
    key      = local.node_pool_taint_key
    operator = "Equal"
    value    = local.node_pool_name
    effect   = "NoSchedule"
  }] : []
  # The chart skips empty values, so every key is always present.
  placement = {
    nodeSelector      = local.node_selector
    tolerations       = local.tolerations
    priorityClassName = local.priority_class_name != null ? local.priority_class_name : ""
  }

  # Empty means no PodDisruptionBudget: the chart renders one only for a
  # non-empty value.
  pod_disruption_budget = { for k, v in { maxUnavailable = 1 } : k => v if var.pod_disruption_budgets_enabled }

  components = {
    frontend = var.frontend
    history  = var.history
    matching = var.matching
    worker   = var.worker
  }

  # Go collects garbage harder as the heap nears GOMEMLIMIT, so a pod slows
  # down under memory pressure instead of being killed at its limit.
  memory_limit_mib = {
    for name, c in merge(local.components, { web = var.web }) :
    name => tonumber(regex("^([0-9]+)", c.memory_limit)[0]) * (endswith(c.memory_limit, "Gi") ? 1024 : 1)
  }

  spread_constraints = {
    for name in concat(keys(local.components), ["web"]) :
    name => var.topology_spread == "off" ? [] : [
      for key in ["topology.kubernetes.io/zone", "kubernetes.io/hostname"] : {
        maxSkew           = 1
        topologyKey       = key
        whenUnsatisfiable = var.topology_spread == "required" ? "DoNotSchedule" : "ScheduleAnyway"
        labelSelector = {
          matchLabels = {
            "app.kubernetes.io/name"      = "temporal"
            "app.kubernetes.io/instance"  = var.name
            "app.kubernetes.io/component" = name
          }
        }
      }
    ]
  }

  component_values = {
    for name, c in local.components : name => merge(
      {
        replicaCount = c.replicas
        resources = {
          requests = { cpu = c.cpu_request, memory = c.memory_request }
          limits   = { memory = c.memory_limit }
        }
        additionalEnv             = [{ name = "GOMEMLIMIT", value = "${floor(local.memory_limit_mib[name] * 0.9)}MiB" }]
        topologySpreadConstraints = local.spread_constraints[name]
        podDisruptionBudget       = local.pod_disruption_budget
        metrics = {
          annotations    = { enabled = var.metrics_prometheus_annotations_enabled }
          serviceMonitor = { enabled = var.metrics_service_monitor_enabled }
        }
      },
    )
  }

  database_tls = var.database_tls_enabled ? {
    enabled                = true
    caFile                 = "${local.database_ca_mount_path}/rds-global-bundle.pem"
    enableHostVerification = true
    serverName             = local.database_host
  } : { enabled = false }

  datastore = {
    for store, settings in {
      default    = { database = var.database_name, max_conns = var.database_max_connections }
      visibility = { database = var.visibility_database_name, max_conns = var.visibility_database_max_connections }
      } : store => {
      sql = {
        pluginName      = "postgres12_pgx"
        driverName      = "postgres12_pgx"
        databaseName    = settings.database
        connectAddr     = "${local.database_host}:${local.database_port}"
        connectProtocol = "tcp"
        user            = local.database_user
        existingSecret  = local.database_secret_name
        secretKey       = "password"
        createDatabase  = var.database_schema_management_enabled
        manageSchema    = var.database_schema_management_enabled
        maxConns        = settings.max_conns
        maxIdleConns    = settings.max_conns
        maxConnLifetime = "1h"
        tls             = local.database_tls
      }
    }
  }

  database_ca_volumes = {
    additionalVolumes      = var.database_tls_enabled ? [{ name = "rds-ca", configMap = { name = local.database_ca_config_map } }] : []
    additionalVolumeMounts = var.database_tls_enabled ? [{ name = "rds-ca", mountPath = local.database_ca_mount_path, readOnly = true }] : []
  }

  image_parts = {
    for name, image in {
      server      = var.server_image
      admin_tools = var.admin_tools_image
      web         = var.web_image
    } : name => regex("^(.*):([^:/]+)$", image)
  }

  web_ingress_annotations = merge(
    local.web_ingress_alb ? merge(
      {
        "alb.ingress.kubernetes.io/scheme"           = "internal"
        "alb.ingress.kubernetes.io/target-type"      = "ip"
        "alb.ingress.kubernetes.io/healthcheck-path" = "/healthz"
      },
      var.web_ingress_certificate_arn != null ? {
        "alb.ingress.kubernetes.io/certificate-arn" = var.web_ingress_certificate_arn
        "alb.ingress.kubernetes.io/listen-ports"    = "[{\"HTTPS\":443}]"
        "alb.ingress.kubernetes.io/ssl-policy"      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
      } : {},
    ) : {},
    var.web_ingress_annotations,
  )

  temporal_values = {
    fullnameOverride = var.name

    server = merge(
      {
        image = {
          repository = local.image_parts.server[0]
          tag        = local.image_parts.server[1]
        }
        # Room for the drains in dynamicConfig: the frontend fails its health
        # check, then drains requests, before the process exits.
        terminationGracePeriodSeconds = 60
        metrics = {
          annotations    = { enabled = var.metrics_prometheus_annotations_enabled }
          serviceMonitor = { enabled = var.metrics_service_monitor_enabled }
        }
        config = {
          logLevel = var.log_level
          persistence = {
            defaultStore     = "default"
            visibilityStore  = "visibility"
            numHistoryShards = var.num_history_shards
            datastores       = local.datastore
          }
          namespaces = {
            create = length(var.temporal_namespaces) > 0
            namespace = [for name, days in var.temporal_namespaces : {
              name      = name
              retention = "${days}d"
            }]
          }
        }
        dynamicConfig = {
          "frontend.shutdownFailHealthCheckDuration" = [{ value = "10s" }]
          "frontend.shutdownDrainDuration"           = [{ value = "30s" }]
          "matching.shutdownDrainDuration"           = [{ value = "10s" }]
          "history.shutdownDrainDuration"            = [{ value = "10s" }]
        }
        tls = {
          internode = {
            enabled           = var.tls_enabled
            secretName        = var.tls_enabled ? local.tls_internode_secret : ""
            requireClientAuth = true
            serverName        = var.tls_enabled ? local.internode_server_name : ""
          }
          frontend = {
            enabled           = var.tls_enabled
            secretName        = var.tls_enabled ? local.tls_frontend_secret : ""
            requireClientAuth = var.tls_frontend_client_auth_required
            serverName        = var.tls_enabled ? local.frontend_host : ""
          }
        }
      },
      local.placement,
      local.database_ca_volumes,
      local.component_values,
    )

    # The admin tools image runs the schema and namespace jobs.
    admintools = merge(
      {
        image = {
          repository = local.image_parts.admin_tools[0]
          tag        = local.image_parts.admin_tools[1]
        }
      },
      local.placement,
      local.database_ca_volumes,
    )

    web = merge(
      {
        enabled      = var.web_enabled
        replicaCount = var.web.replicas
        image = {
          repository = local.image_parts.web[0]
          tag        = local.image_parts.web[1]
        }
        resources = {
          requests = { cpu = var.web.cpu_request, memory = var.web.memory_request }
          limits   = { memory = var.web.memory_limit }
        }
        topologySpreadConstraints = local.spread_constraints.web
        tls = {
          enabled                = var.tls_enabled
          secretName             = var.tls_enabled ? local.tls_frontend_secret : ""
          serverName             = var.tls_enabled ? local.frontend_host : ""
          enableHostVerification = var.tls_enabled
        }
        ingress = {
          enabled     = var.web_ingress_enabled
          className   = var.web_ingress_class_name
          annotations = local.web_ingress_annotations
          hosts       = [var.web_ingress_host != null ? "${var.web_ingress_host}/" : "/"]
          tls         = []
        }
      },
      local.placement,
      { podDisruptionBudget = var.web.replicas > 1 ? local.pod_disruption_budget : {} },
    )

    # The schema job runs as an ordinary Job rather than a pre-install hook:
    # hooks run before any object of the release exists, and the job needs the
    # database Secret and CA bundle the resources release creates. The servers
    # restart until the schema is in place, and the install waits for the job.
    schema = {
      useHelmHooks = false
    }
  }

  resources_values = {
    temporal = {
      releaseName = var.name
    }
    database = {
      secretName = local.database_secret_name
      secretKey  = "password"
      externalSecret = {
        enabled              = local.database_external_secret
        secretStoreName      = var.database_password_secret_store_name
        secretStoreKind      = "ClusterSecretStore"
        remoteSecretName     = local.database_external_secret ? var.database_password_secret_arn : ""
        remoteSecretProperty = var.database_password_secret_property
        refreshInterval      = var.database_password_refresh_interval
      }
      caBundle = {
        enabled       = var.database_tls_enabled
        configMapName = local.database_ca_config_map
      }
    }
    tls = {
      enabled      = var.tls_enabled
      caSecretName = local.tls_ca_secret_name
      issuerName   = local.tls_ca_secret_name
      internode = {
        secretName = local.tls_internode_secret
        dnsNames   = [local.internode_server_name]
      }
      frontend = {
        secretName = local.tls_frontend_secret
        dnsNames = [
          local.frontend_host,
          "${var.name}-frontend",
          "${local.frontend_host}.cluster.local",
        ]
      }
    }
    priorityClass = {
      enabled = var.priority_class_creation_enabled
      name    = coalesce(local.priority_class_name, "${var.name}-critical")
      value   = var.priority_class_value
    }
    nodePool = {
      enabled            = var.node_pool_creation_enabled
      name               = local.node_pool_name
      ec2NodeClassName   = var.node_pool.ec2_node_class_name
      capacityTypes      = var.node_pool.capacity_types
      instanceCategories = var.node_pool.instance_categories
      architectures      = var.node_pool.architectures
      cpuLimit           = var.node_pool.cpu_limit
      consolidateAfter   = var.node_pool.consolidate_after
      taint = {
        key   = local.node_pool_taint_key
        value = local.node_pool_name
      }
    }
    networkPolicy = {
      enabled                  = var.network_policy_enabled
      frontendClientNamespaces = var.network_policy_frontend_client_namespaces
      webClientNamespaces      = var.network_policy_web_client_namespaces
      webClientCidrs           = local.network_policy_web_cidrs
      metricsNamespaces        = var.network_policy_metrics_namespaces
    }
    metrics = {
      otlp = {
        enabled  = local.metrics_otlp_enabled
        endpoint = local.metrics_otlp_enabled ? var.metrics_otlp_endpoint : ""
        keep     = var.metrics_otlp_metric_families
        image    = var.metrics_otlp_collector_image
      }
    }
  }
}
