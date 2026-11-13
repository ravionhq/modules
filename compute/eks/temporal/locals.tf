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
  internal_frontend_host = "${var.name}-internal-frontend.${var.namespace}.svc"
  internal_frontend_port = 7236
  web_host               = "${var.name}-web.${var.namespace}.svc"
  internode_server_name  = "${var.name}-internode.${var.namespace}.svc"
  tls_frontend_secret    = "${var.name}-frontend-tls"
  tls_internode_secret   = "${var.name}-internode-tls"
  resources_release_name = "${var.name}-resources"

  ##############################################################################
  # Certificate authority
  ##############################################################################

  # The module's own Issuer signs with a CA it creates (self_signed) or with an
  # existing CA key pair Secret (secret). An existing issuer is used as is.
  tls_module_issuer_name = "${var.name}-ca"
  tls_issuer_ref = var.tls_ca_source == "issuer" && var.tls_issuer != null ? {
    name  = var.tls_issuer.name
    kind  = var.tls_issuer.kind
    group = var.tls_issuer.group
    } : {
    name  = local.tls_module_issuer_name
    kind  = "Issuer"
    group = "cert-manager.io"
  }
  tls_ca_key_pair_secret = var.tls_ca_source == "secret" ? coalesce(var.tls_ca_secret_name, "${var.name}-ca") : "${var.name}-ca"

  ##############################################################################
  # JWT authorization
  ##############################################################################

  jwks_served       = var.jwt_auth_enabled && var.jwt_auth_jwks_source == "secrets_manager"
  jwks_service_name = "${var.name}-jwks"
  jwks_key_urls     = local.jwks_served ? ["http://${local.jwks_service_name}.${var.namespace}.svc:8080/jwks.json"] : var.jwt_auth_jwks_urls

  authorization = merge(
    {
      authorizer           = "default"
      claimMapper          = "default"
      permissionsClaimName = var.jwt_auth_permissions_claim_name
      jwtKeyProvider = {
        keySourceURIs   = local.jwks_key_urls
        refreshInterval = var.jwt_auth_jwks_refresh_interval
      }
    },
    { for k, v in { audience = var.jwt_auth_audience } : k => v if v != null },
  )

  # With the authorizer on, the Web UI either forwards each signed-in user's
  # token to the frontend, or acts as admin through the internal frontend.
  web_via_internal_frontend = var.jwt_auth_enabled && var.web_internal_frontend_enabled

  ##############################################################################
  # Exposure: NLB, Tailscale, Web UI host
  ##############################################################################

  frontend_nlb_name = coalesce(var.frontend_nlb_name, trimsuffix(substr("${var.cluster_name}-${var.name}", 0, 32), "-"))

  tailscale_frontend_hostname = coalesce(var.tailscale_frontend_hostname, "${var.name}-frontend")
  tailscale_web_hostname      = coalesce(var.tailscale_web_hostname, var.name)

  web_ingress_alb = var.web_ingress_enabled && var.web_ingress_class_name == "alb"

  # Where people open the Web UI: the tailnet first, then the ingress host.
  web_base_url = (
    var.web_enabled && var.tailscale_web_enabled && var.tailscale_tailnet_domain != null ? "https://${local.tailscale_web_hostname}.${var.tailscale_tailnet_domain}" :
    var.web_enabled && var.web_ingress_enabled && var.web_ingress_host != null ? "${var.web_ingress_certificate_arn != null || !local.web_ingress_alb ? "https" : "http"}://${var.web_ingress_host}" :
    null
  )

  ##############################################################################
  # Web UI sign-in (OIDC)
  ##############################################################################

  oidc_preset_issuer = {
    google          = "https://accounts.google.com"
    okta            = ""
    microsoft_entra = ""
    generic         = ""
  }
  oidc_preset_scopes = {
    google          = ["openid", "profile", "email"]
    okta            = ["openid", "profile", "email", "offline_access"]
    microsoft_entra = ["openid", "profile", "email", "offline_access"]
    generic         = []
  }
  oidc_preset_label = {
    google          = "Google"
    okta            = "Okta"
    microsoft_entra = "Microsoft"
    generic         = "Single sign-on"
  }
  oidc_enabled      = var.web_enabled && var.web_oidc_enabled
  oidc_issuer_url   = var.web_oidc_issuer_url != null ? var.web_oidc_issuer_url : local.oidc_preset_issuer[var.web_oidc_provider]
  oidc_scopes       = var.web_oidc_scopes != null ? var.web_oidc_scopes : local.oidc_preset_scopes[var.web_oidc_provider]
  oidc_callback_url = var.web_oidc_callback_url != null ? var.web_oidc_callback_url : (local.web_base_url != null ? "${local.web_base_url}/auth/sso/callback" : null)
  oidc_secret_name  = "${var.name}-web-oidc"

  oidc_env = local.oidc_enabled ? concat(
    [
      { name = "TEMPORAL_AUTH_ENABLED", value = "true" },
      { name = "TEMPORAL_AUTH_TYPE", value = "oidc" },
      { name = "TEMPORAL_AUTH_LABEL", value = local.oidc_preset_label[var.web_oidc_provider] },
      { name = "TEMPORAL_AUTH_PROVIDER_URL", value = local.oidc_issuer_url },
      { name = "TEMPORAL_AUTH_ISSUER_URL", value = local.oidc_issuer_url },
      { name = "TEMPORAL_AUTH_CALLBACK_URL", value = coalesce(local.oidc_callback_url, "unset") },
      { name = "TEMPORAL_AUTH_SCOPES", value = join(",", local.oidc_scopes) },
    ],
    # The frontend can verify an ID token from the provider, not its opaque
    # access token, so forward the ID token when the frontend checks tokens.
    var.jwt_auth_enabled && !local.web_via_internal_frontend ? [{ name = "TEMPORAL_AUTH_USE_ID_TOKEN_AS_BEARER", value = "true" }] : [],
  ) : []

  ##############################################################################
  # Network policy sources
  ##############################################################################

  web_ingress_vpc_cidr_needed = var.network_policy_enabled && ((var.web_enabled && var.web_ingress_enabled) || (var.frontend_nlb_enabled && length(var.frontend_nlb_subnet_ids) == 0))
  vpc_cidr                    = local.web_ingress_vpc_cidr_needed ? data.aws_vpc.cluster[0].cidr_block : null

  network_policy_web_cidrs = distinct(concat(
    var.network_policy_web_client_cidrs,
    var.web_enabled && var.web_ingress_enabled && local.vpc_cidr != null ? [local.vpc_cidr] : [],
  ))

  # The NLB keeps client addresses, so its allowed sources reach the pods as
  # they are. Its health checks come from its own addresses in its subnets.
  network_policy_frontend_cidrs = var.frontend_nlb_enabled ? distinct(concat(
    var.frontend_nlb_source_cidrs,
    length(var.frontend_nlb_subnet_ids) > 0 ? [for s in data.aws_subnet.frontend_nlb : s.cidr_block] : compact([local.vpc_cidr]),
  )) : []

  # An empty namespace list already admits every namespace, Tailscale's too.
  network_policy_frontend_namespaces = length(var.network_policy_frontend_client_namespaces) > 0 && var.tailscale_frontend_enabled ? distinct(concat(var.network_policy_frontend_client_namespaces, [var.tailscale_namespace])) : var.network_policy_frontend_client_namespaces
  network_policy_web_namespaces      = length(var.network_policy_web_client_namespaces) > 0 && var.tailscale_web_enabled ? distinct(concat(var.network_policy_web_client_namespaces, [var.tailscale_namespace])) : var.network_policy_web_client_namespaces

  metrics_otlp_enabled = var.metrics_otlp_endpoint != null && var.metrics_otlp_endpoint != ""

  ##############################################################################
  # Placement and per-service values
  ##############################################################################

  priority_class_name = var.priority_class_creation_enabled ? coalesce(var.priority_class_name, "${var.name}-critical") : var.priority_class_name
  node_pool_name      = var.name
  node_pool_taint_key = "ravion.com/dedicated"

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
    frontend            = var.frontend
    history             = var.history
    matching            = var.matching
    worker              = var.worker
    "internal-frontend" = var.internal_frontend
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

  frontend_env_secret_name = "${var.name}-frontend-env"
  server_files_secret_name = "${var.name}-server-files"

  # Extra frontend environment: plain values, then values synced from Secrets
  # Manager into frontend_env_secret_name.
  frontend_custom_env = concat(
    [for k, v in var.frontend_extra_env : { name = k, value = v }],
    [for k, v in var.frontend_secret_env : { name = k, valueFrom = { secretKeyRef = { name = local.frontend_env_secret_name, key = k } } }],
  )

  component_values = {
    for name, c in local.components : name => {
      enabled      = name != "internal-frontend" || var.jwt_auth_enabled
      replicaCount = c.replicas
      resources = {
        requests = { cpu = c.cpu_request, memory = c.memory_request }
        limits   = { memory = c.memory_limit }
      }
      additionalEnv = concat(
        [{ name = "GOMEMLIMIT", value = "${floor(local.memory_limit_mib[name] * 0.9)}MiB" }],
        [for e in local.frontend_custom_env : e if name == "frontend"],
      )
      topologySpreadConstraints = local.spread_constraints[name]
      podDisruptionBudget       = local.pod_disruption_budget
      metrics = {
        annotations    = { enabled = var.metrics_prometheus_annotations_enabled }
        serviceMonitor = { enabled = var.metrics_service_monitor_enabled }
      }
    }
  }

  ##############################################################################
  # Database
  ##############################################################################

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

  database_ca_volume       = var.database_tls_enabled ? [{ name = "rds-ca", configMap = { name = local.database_ca_config_map } }] : []
  database_ca_volume_mount = var.database_tls_enabled ? [{ name = "rds-ca", mountPath = local.database_ca_mount_path, readOnly = true }] : []

  # Secrets Manager files for the server pods. A subPath mount does not pick
  # up later changes, so restart the pods after a secret changes.
  server_files_volume = length(var.server_secret_files) > 0 ? [{ name = "secret-files", secret = { secretName = local.server_files_secret_name } }] : []
  server_files_keys   = { for i, path in sort(keys(var.server_secret_files)) : path => "file-${i}" }
  server_files_mounts = [for path, key in local.server_files_keys : {
    name      = "secret-files"
    mountPath = path
    subPath   = key
    readOnly  = true
  }]

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

  ##############################################################################
  # Namespace and search attribute setup
  ##############################################################################

  # The job reaches the cluster as the admin tools do: through the internal
  # frontend with the internode certificate when tokens are required, otherwise
  # through the frontend.
  setup_address  = var.jwt_auth_enabled ? "${local.internal_frontend_host}:${local.internal_frontend_port}" : "${local.frontend_host}:${local.frontend_port}"
  setup_tls      = var.tls_enabled
  setup_tls_name = var.jwt_auth_enabled ? local.internode_server_name : local.frontend_host
  setup_tls_cert = var.jwt_auth_enabled ? local.tls_internode_secret : local.tls_frontend_secret

  # Idempotent on every deploy: creates missing namespaces, applies retention,
  # and registers missing search attributes. Attributes are never removed.
  setup_script = join("\n", concat(
    [
      "set -eu",
      "until temporal operator cluster health >/dev/null 2>&1; do echo 'waiting for Temporal'; sleep 5; done",
    ],
    flatten([
      for ns_name, ns in var.temporal_namespaces : concat(
        [
          "temporal operator namespace describe -n '${ns_name}' >/dev/null 2>&1 || temporal operator namespace create -n '${ns_name}' --retention ${ns.retention_days}d",
          "temporal operator namespace update -n '${ns_name}' --retention ${ns.retention_days}d",
          "existing=$(temporal operator search-attribute list -n '${ns_name}')",
        ],
        [
          for attr, type in ns.search_attributes :
          "echo \"$existing\" | grep -qw '${attr}' || temporal operator search-attribute create -n '${ns_name}' --name '${attr}' --type ${type}"
        ],
      )
    ]),
  ))

  setup_job = {
    apiVersion = "batch/v1"
    kind       = "Job"
    metadata = {
      name      = "${var.name}-namespace-setup"
      namespace = var.namespace
      labels = {
        "app.kubernetes.io/name"      = "temporal"
        "app.kubernetes.io/instance"  = var.name
        "app.kubernetes.io/component" = "namespace-setup"
      }
      annotations = {
        "helm.sh/hook"               = "post-install,post-upgrade"
        "helm.sh/hook-weight"        = "1"
        "helm.sh/hook-delete-policy" = "before-hook-creation,hook-succeeded"
      }
    }
    spec = {
      backoffLimit          = 10
      activeDeadlineSeconds = 900
      template = {
        metadata = {
          labels = {
            "app.kubernetes.io/name"      = "temporal"
            "app.kubernetes.io/instance"  = var.name
            "app.kubernetes.io/component" = "namespace-setup"
          }
        }
        spec = merge(
          {
            restartPolicy                = "OnFailure"
            automountServiceAccountToken = false
            containers = [{
              name    = "namespace-setup"
              image   = var.admin_tools_image
              command = ["/bin/sh", "-c"]
              args    = [local.setup_script]
              env = concat(
                [{ name = "TEMPORAL_ADDRESS", value = local.setup_address }],
                local.setup_tls ? [
                  { name = "TEMPORAL_TLS", value = "true" },
                  { name = "TEMPORAL_TLS_SERVER_NAME", value = local.setup_tls_name },
                  { name = "TEMPORAL_TLS_SERVER_CA_CERT_PATH", value = "/etc/temporal/tls/client/ca.crt" },
                  { name = "TEMPORAL_TLS_CLIENT_CERT_PATH", value = "/etc/temporal/tls/client/tls.crt" },
                  { name = "TEMPORAL_TLS_CLIENT_KEY_PATH", value = "/etc/temporal/tls/client/tls.key" },
                ] : [],
              )
              resources = {
                requests = { cpu = "50m", memory = "64Mi" }
                limits   = { memory = "256Mi" }
              }
              volumeMounts = local.setup_tls ? [{ name = "client-tls", mountPath = "/etc/temporal/tls/client", readOnly = true }] : []
            }]
            volumes = local.setup_tls ? [{ name = "client-tls", secret = { secretName = local.setup_tls_cert } }] : []
          },
          local.placement,
        )
      }
    }
  }

  ##############################################################################
  # Upstream chart values
  ##############################################################################

  temporal_values = {
    fullnameOverride = var.name

    # The setup job runs after every install and upgrade, once the servers are up.
    extraObjects = length(var.temporal_namespaces) > 0 ? [yamlencode(local.setup_job)] : []

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
        config = merge(
          {
            logLevel = var.log_level
            persistence = {
              defaultStore     = "default"
              visibilityStore  = "visibility"
              numHistoryShards = var.num_history_shards
              datastores       = local.datastore
            }
            # Namespaces and their search attributes come from the setup job.
            namespaces = { create = false }
          },
          { for k, v in { authorization = local.authorization } : k => v if var.jwt_auth_enabled },
        )
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
        additionalVolumes      = concat(local.database_ca_volume, local.server_files_volume)
        additionalVolumeMounts = concat(local.database_ca_volume_mount, local.server_files_mounts)
      },
      local.placement,
      local.component_values,
    )

    # The admin tools image runs the schema job.
    admintools = merge(
      {
        image = {
          repository = local.image_parts.admin_tools[0]
          tag        = local.image_parts.admin_tools[1]
        }
        additionalVolumes      = local.database_ca_volume
        additionalVolumeMounts = local.database_ca_volume_mount
      },
      local.placement,
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
          secretName             = !var.tls_enabled ? "" : local.web_via_internal_frontend ? local.tls_internode_secret : local.tls_frontend_secret
          serverName             = !var.tls_enabled ? "" : local.web_via_internal_frontend ? local.internode_server_name : local.frontend_host
          enableHostVerification = var.tls_enabled
        }
        ingress = {
          enabled     = var.web_ingress_enabled
          className   = var.web_ingress_class_name
          annotations = local.web_ingress_annotations
          hosts       = [var.web_ingress_host != null ? "${var.web_ingress_host}/" : "/"]
          tls         = []
        }
        additionalEnv           = local.oidc_env
        additionalEnvSecretName = local.oidc_enabled ? local.oidc_secret_name : ""
      },
      { for k, v in { temporalAddress = "${local.internal_frontend_host}:${local.internal_frontend_port}" } : k => v if local.web_via_internal_frontend },
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

  ##############################################################################
  # temporal-resources chart values
  ##############################################################################

  resources_values = {
    temporal = {
      releaseName = var.name
    }
    externalSecrets = {
      secretStoreName = var.external_secrets_store_name
      secretStoreKind = "ClusterSecretStore"
    }
    database = {
      secretName = local.database_secret_name
      secretKey  = "password"
      externalSecret = {
        enabled              = local.database_external_secret
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
      enabled  = var.tls_enabled
      caSource = var.tls_ca_source
      # The module's own Issuer (self_signed and secret), and the CA key pair
      # it signs with.
      issuerName   = local.tls_module_issuer_name
      caSecretName = local.tls_ca_key_pair_secret
      issuerRef    = local.tls_issuer_ref
      internode = {
        secretName = local.tls_internode_secret
        dnsNames   = [local.internode_server_name]
      }
      frontend = {
        secretName = local.tls_frontend_secret
        dnsNames = distinct(concat(
          [
            local.frontend_host,
            "${var.name}-frontend",
            "${local.frontend_host}.cluster.local",
          ],
          var.tailscale_frontend_enabled && var.tailscale_tailnet_domain != null ? ["${local.tailscale_frontend_hostname}.${var.tailscale_tailnet_domain}"] : [],
          var.tls_frontend_extra_dns_names,
        ))
      }
    }
    jwks = {
      enabled          = local.jwks_served
      name             = local.jwks_service_name
      remoteSecretName = local.jwks_served ? var.jwt_auth_jwks_secret_arn : ""
      remoteProperty   = var.jwt_auth_jwks_secret_property != null ? var.jwt_auth_jwks_secret_property : ""
      refreshInterval  = var.jwt_auth_jwks_refresh_interval
      image            = var.jwt_auth_jwks_server_image
    }
    frontendEnv = {
      secretName = local.frontend_env_secret_name
      items = [for k, v in var.frontend_secret_env : {
        key            = k
        remoteSecret   = v.secret_arn
        remoteProperty = v.property != null ? v.property : ""
      }]
    }
    serverFiles = {
      secretName = local.server_files_secret_name
      items = [for path, key in local.server_files_keys : {
        key            = key
        remoteSecret   = var.server_secret_files[path].secret_arn
        remoteProperty = var.server_secret_files[path].property != null ? var.server_secret_files[path].property : ""
      }]
    }
    webOidc = {
      enabled              = local.oidc_enabled
      secretName           = local.oidc_secret_name
      remoteSecretName     = local.oidc_enabled ? var.web_oidc_client_secret_arn : ""
      clientIdProperty     = var.web_oidc_client_id_property
      clientSecretProperty = var.web_oidc_client_secret_property
    }
    frontendNlb = {
      enabled                   = var.frontend_nlb_enabled
      name                      = local.frontend_nlb_name
      subnetIds                 = var.frontend_nlb_subnet_ids
      sourceRanges              = var.frontend_nlb_source_cidrs
      crossZoneEnabled          = var.frontend_nlb_cross_zone_enabled
      deletionProtectionEnabled = var.frontend_nlb_deletion_protection_enabled
    }
    tailscale = {
      frontend = {
        enabled  = var.tailscale_frontend_enabled
        hostname = local.tailscale_frontend_hostname
        tags     = var.tailscale_frontend_tags
      }
      web = {
        enabled  = var.web_enabled && var.tailscale_web_enabled
        hostname = local.tailscale_web_hostname
        tags     = var.tailscale_web_tags
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
      frontendClientNamespaces = local.network_policy_frontend_namespaces
      frontendClientCidrs      = local.network_policy_frontend_cidrs
      webClientNamespaces      = local.network_policy_web_namespaces
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
