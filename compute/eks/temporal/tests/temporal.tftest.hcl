mock_provider "aws" {
  mock_data "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:us-east-2:123456789012:cluster/test-cluster"
      endpoint              = "https://mock.eks.amazonaws.com"
      certificate_authority = [{ data = "bW9jay1jYQ==" }]
      vpc_config = [{
        vpc_id                    = "vpc-12345678"
        cluster_security_group_id = "sg-12345678"
        control_plane_egress_mode = ""
        endpoint_private_access   = true
        endpoint_public_access    = false
        public_access_cidrs       = []
        security_group_ids        = []
        subnet_ids                = []
      }]
    }
  }
  mock_data "aws_vpc" {
    defaults = { cidr_block = "10.20.0.0/16" }
  }
  mock_data "aws_rds_cluster" {
    defaults = {
      engine          = "aurora-postgresql"
      endpoint        = "temporal-db.cluster-abc123.us-east-2.rds.amazonaws.com"
      port            = 5432
      master_username = "temporal_admin"
    }
  }
}
mock_provider "helm" {}

variables {
  cluster_name                 = "test-cluster"
  region                       = "us-east-2"
  database_cluster_identifier  = "temporal-db"
  database_password_secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:temporal-db-AbCdEf"
}

run "defaults_install_both_releases_against_the_database" {
  command = plan

  assert {
    condition     = helm_release.temporal.repository == "https://go.temporal.io/helm-charts" && helm_release.temporal.chart == "temporal" && helm_release.temporal.version == "1.8.0"
    error_message = "Temporal must install the pinned upstream chart."
  }
  assert {
    condition     = helm_release.temporal.name == "temporal" && helm_release.temporal.namespace == "temporal" && helm_release.temporal_resources.namespace == "temporal"
    error_message = "Both releases must install into the module's namespace."
  }
  assert {
    condition     = helm_release.temporal_resources.create_namespace && !helm_release.temporal.create_namespace
    error_message = "Only the first release creates the namespace."
  }
  assert {
    condition     = helm_release.temporal.wait && helm_release.temporal.wait_for_jobs && helm_release.temporal.timeout == 900
    error_message = "The install must wait for the schema job and the servers."
  }
  assert {
    condition     = yamldecode(helm_release.temporal.values[0]).fullnameOverride == "temporal"
    error_message = "Services must be prefixed with the release name."
  }
  assert {
    condition     = yamldecode(helm_release.temporal.values[0]).server.config.persistence.numHistoryShards == 512
    error_message = "The default history shard count must be 512."
  }
  assert {
    condition = alltrue([
      for store, db in { default = "temporal", visibility = "temporal_visibility" } :
      yamldecode(helm_release.temporal.values[0]).server.config.persistence.datastores[store].sql.databaseName == db &&
      yamldecode(helm_release.temporal.values[0]).server.config.persistence.datastores[store].sql.connectAddr == "temporal-db.cluster-abc123.us-east-2.rds.amazonaws.com:5432" &&
      yamldecode(helm_release.temporal.values[0]).server.config.persistence.datastores[store].sql.user == "temporal_admin" &&
      yamldecode(helm_release.temporal.values[0]).server.config.persistence.datastores[store].sql.existingSecret == "temporal-db" &&
      yamldecode(helm_release.temporal.values[0]).server.config.persistence.datastores[store].sql.pluginName == "postgres12_pgx"
    ])
    error_message = "Both datastores must point at the Aurora cluster with the synced password Secret."
  }
  assert {
    condition     = yamldecode(helm_release.temporal.values[0]).server.config.persistence.datastores.default.sql.tls.caFile == "/etc/temporal/rds-ca/rds-global-bundle.pem" && yamldecode(helm_release.temporal.values[0]).server.config.persistence.datastores.default.sql.tls.enableHostVerification
    error_message = "The database connection must verify the server certificate against the RDS CA bundle."
  }
  assert {
    condition     = yamldecode(helm_release.temporal.values[0]).server.additionalVolumes[0].configMap.name == "temporal-rds-ca" && yamldecode(helm_release.temporal.values[0]).admintools.additionalVolumes[0].configMap.name == "temporal-rds-ca"
    error_message = "The servers and the schema jobs must mount the RDS CA bundle."
  }
  assert {
    condition     = !yamldecode(helm_release.temporal.values[0]).schema.useHelmHooks
    error_message = "The schema job must run as an ordinary Job so it can read the Secret the resources release creates."
  }
  assert {
    condition     = !yamldecode(helm_release.temporal.values[0]).server.config.namespaces.create && length(yamldecode(helm_release.temporal.values[0]).extraObjects) == 1 && strcontains(yamldecode(helm_release.temporal.values[0]).extraObjects[0], "namespace create -n 'default' --retention 7d")
    error_message = "The setup job, not the chart's, must create the default Temporal namespace with 7 days of retention."
  }
  assert {
    condition = (
      yamldecode(helm_release.temporal_resources.values[0]).database.externalSecret.enabled &&
      yamldecode(helm_release.temporal_resources.values[0]).database.externalSecret.remoteSecretName == "arn:aws:secretsmanager:us-east-2:123456789012:secret:temporal-db-AbCdEf" &&
      yamldecode(helm_release.temporal_resources.values[0]).externalSecrets.secretStoreName == "ravion-aws" &&
      yamldecode(helm_release.temporal_resources.values[0]).database.secretName == "temporal-db"
    )
    error_message = "The password must be synced from Secrets Manager into the Secret Temporal reads."
  }
  assert {
    condition     = !strcontains(helm_release.temporal.values[0], "secretsmanager") && !strcontains(helm_release.temporal.values[0], "password:")
    error_message = "Neither a password nor the Secrets Manager reference may reach the Temporal chart's values."
  }
  assert {
    condition     = yamldecode(helm_release.temporal_resources.values[0]).networkPolicy.enabled && length(yamldecode(helm_release.temporal_resources.values[0]).networkPolicy.webClientCidrs) == 0
    error_message = "Network policies are on by default and admit no CIDRs without an ingress."
  }
  assert {
    condition     = !yamldecode(helm_release.temporal_resources.values[0]).nodePool.enabled && !yamldecode(helm_release.temporal_resources.values[0]).priorityClass.enabled && !yamldecode(helm_release.temporal_resources.values[0]).tls.enabled && !yamldecode(helm_release.temporal_resources.values[0]).metrics.otlp.enabled
    error_message = "Optional resources must be off by default."
  }
  assert {
    condition     = output.frontend_address == "temporal-frontend.temporal.svc:7233" && output.web_address == "http://temporal-web.temporal.svc:8080" && output.web_url == null
    error_message = "Outputs must give the in-cluster frontend and Web UI addresses."
  }
}

run "services_get_resources_spread_budgets_and_gomemlimit" {
  command = plan

  variables {
    history = { replicas = 3, memory_limit = "2Gi" }
  }

  assert {
    condition     = yamldecode(helm_release.temporal.values[0]).server.history.replicaCount == 3 && yamldecode(helm_release.temporal.values[0]).server.history.resources.limits.memory == "2Gi" && yamldecode(helm_release.temporal.values[0]).server.history.resources.requests.cpu == "500m"
    error_message = "History must take the requested replicas and keep the default CPU request."
  }
  assert {
    condition     = yamldecode(helm_release.temporal.values[0]).server.history.additionalEnv[0].value == "1843MiB" && yamldecode(helm_release.temporal.values[0]).server.frontend.additionalEnv[0].value == "460MiB"
    error_message = "GOMEMLIMIT must sit at 90% of each service's memory limit."
  }
  assert {
    condition     = yamldecode(helm_release.temporal.values[0]).server.frontend.podDisruptionBudget.maxUnavailable == 1
    error_message = "Each service must get a PodDisruptionBudget."
  }
  assert {
    condition = alltrue([
      for c in yamldecode(helm_release.temporal.values[0]).server.matching.topologySpreadConstraints :
      c.whenUnsatisfiable == "ScheduleAnyway" && c.labelSelector.matchLabels["app.kubernetes.io/component"] == "matching" && c.labelSelector.matchLabels["app.kubernetes.io/instance"] == "temporal"
    ]) && length(yamldecode(helm_release.temporal.values[0]).server.matching.topologySpreadConstraints) == 2
    error_message = "Replicas must be spread across zones and nodes, preferred by default."
  }
}

run "required_spread_and_no_budgets" {
  command = plan

  variables {
    topology_spread                = "required"
    pod_disruption_budgets_enabled = false
  }

  assert {
    condition     = alltrue([for c in yamldecode(helm_release.temporal.values[0]).server.history.topologySpreadConstraints : c.whenUnsatisfiable == "DoNotSchedule"])
    error_message = "Required spread must refuse to schedule replicas that would break it."
  }
  assert {
    condition     = length(yamldecode(helm_release.temporal.values[0]).server.history.podDisruptionBudget) == 0
    error_message = "Budgets must be omitted when disabled."
  }
}

run "dedicated_node_pool_and_priority_class" {
  command = plan

  variables {
    node_pool_creation_enabled      = true
    priority_class_creation_enabled = true
    node_pool                       = { cpu_limit = 64 }
  }

  assert {
    condition     = yamldecode(helm_release.temporal.values[0]).server.nodeSelector["karpenter.sh/nodepool"] == "temporal" && yamldecode(helm_release.temporal.values[0]).server.tolerations[0].key == "ravion.com/dedicated" && yamldecode(helm_release.temporal.values[0]).admintools.nodeSelector["karpenter.sh/nodepool"] == "temporal" && yamldecode(helm_release.temporal.values[0]).web.tolerations[0].value == "temporal"
    error_message = "Every Temporal pod must select and tolerate the dedicated NodePool."
  }
  assert {
    condition     = yamldecode(helm_release.temporal.values[0]).server.priorityClassName == "temporal-critical" && yamldecode(helm_release.temporal_resources.values[0]).priorityClass.enabled && yamldecode(helm_release.temporal_resources.values[0]).priorityClass.name == "temporal-critical"
    error_message = "The created PriorityClass must be the one the pods use."
  }
  assert {
    condition     = yamldecode(helm_release.temporal_resources.values[0]).nodePool.enabled && yamldecode(helm_release.temporal_resources.values[0]).nodePool.cpuLimit == 64 && yamldecode(helm_release.temporal_resources.values[0]).nodePool.capacityTypes[0] == "on-demand"
    error_message = "The NodePool must take the requested limits and stay on-demand by default."
  }
  assert {
    condition     = output.node_pool_name == "temporal" && output.priority_class_name == "temporal-critical"
    error_message = "Outputs must name the NodePool and PriorityClass."
  }
}

run "tls_wires_certificates_into_servers_and_web" {
  command = plan

  variables {
    tls_enabled = true
  }

  assert {
    condition     = yamldecode(helm_release.temporal.values[0]).server.tls.internode.enabled && yamldecode(helm_release.temporal.values[0]).server.tls.internode.secretName == "temporal-internode-tls" && yamldecode(helm_release.temporal.values[0]).server.tls.internode.serverName == "temporal-internode.temporal.svc"
    error_message = "Internode traffic must use mutual TLS with the internode certificate."
  }
  assert {
    condition     = yamldecode(helm_release.temporal.values[0]).server.tls.frontend.enabled && !yamldecode(helm_release.temporal.values[0]).server.tls.frontend.requireClientAuth && yamldecode(helm_release.temporal.values[0]).server.tls.frontend.serverName == "temporal-frontend.temporal.svc"
    error_message = "The frontend must serve TLS without requiring client certificates by default."
  }
  assert {
    condition     = yamldecode(helm_release.temporal.values[0]).web.tls.enabled && yamldecode(helm_release.temporal.values[0]).web.tls.secretName == "temporal-frontend-tls" && yamldecode(helm_release.temporal.values[0]).web.tls.enableHostVerification
    error_message = "The Web UI must verify the frontend certificate."
  }
  assert {
    condition     = yamldecode(helm_release.temporal_resources.values[0]).tls.enabled && contains(yamldecode(helm_release.temporal_resources.values[0]).tls.frontend.dnsNames, "temporal-frontend.temporal.svc")
    error_message = "The frontend certificate must cover the frontend Service name."
  }
  assert {
    condition     = output.tls_ca_secret_name == "temporal-frontend-tls" && output.tls_server_name == "temporal-frontend.temporal.svc"
    error_message = "Outputs must tell clients what to trust and verify."
  }
}

run "internal_alb_ingress_admits_the_vpc" {
  command = plan

  variables {
    web_ingress_enabled         = true
    web_ingress_host            = "temporal.internal.example.com"
    web_ingress_certificate_arn = "arn:aws:acm:us-east-2:123456789012:certificate/abc"
  }

  assert {
    condition     = yamldecode(helm_release.temporal.values[0]).web.ingress.enabled && yamldecode(helm_release.temporal.values[0]).web.ingress.className == "alb" && yamldecode(helm_release.temporal.values[0]).web.ingress.annotations["alb.ingress.kubernetes.io/scheme"] == "internal"
    error_message = "The Web UI ingress must be an internal ALB."
  }
  assert {
    condition     = yamldecode(helm_release.temporal.values[0]).web.ingress.annotations["alb.ingress.kubernetes.io/certificate-arn"] == "arn:aws:acm:us-east-2:123456789012:certificate/abc" && yamldecode(helm_release.temporal.values[0]).web.ingress.hosts[0] == "temporal.internal.example.com/"
    error_message = "The ALB must serve HTTPS with the given certificate on the given host."
  }
  assert {
    condition     = contains(yamldecode(helm_release.temporal_resources.values[0]).networkPolicy.webClientCidrs, "10.20.0.0/16")
    error_message = "The network policy must admit the ALB's addresses from the VPC."
  }
  assert {
    condition     = output.web_url == "https://temporal.internal.example.com"
    error_message = "web_url must use HTTPS when a certificate is set."
  }
}

run "metrics_forwarder_and_service_monitors" {
  command = plan

  variables {
    metrics_otlp_endpoint           = "http://otel.monitoring.svc.cluster.local:4317"
    metrics_service_monitor_enabled = true
  }

  assert {
    condition     = yamldecode(helm_release.temporal_resources.values[0]).metrics.otlp.enabled && yamldecode(helm_release.temporal_resources.values[0]).metrics.otlp.endpoint == "http://otel.monitoring.svc.cluster.local:4317" && contains(yamldecode(helm_release.temporal_resources.values[0]).metrics.otlp.keep, "service_requests")
    error_message = "The forwarder must push to the given endpoint with the curated families."
  }
  assert {
    condition     = yamldecode(helm_release.temporal.values[0]).server.metrics.serviceMonitor.enabled && yamldecode(helm_release.temporal.values[0]).server.history.metrics.serviceMonitor.enabled
    error_message = "ServiceMonitors must be enabled for every service."
  }
}

run "existing_kubernetes_secret_needs_no_secret_arn" {
  command = plan

  variables {
    database_password_source                 = "kubernetes_secret"
    database_password_secret_arn             = null
    database_password_kubernetes_secret_name = "my-db-password"
    database_tls_enabled                     = false
  }

  assert {
    condition     = !yamldecode(helm_release.temporal_resources.values[0]).database.externalSecret.enabled && yamldecode(helm_release.temporal.values[0]).server.config.persistence.datastores.default.sql.existingSecret == "my-db-password"
    error_message = "An existing Secret must be read as-is, without an ExternalSecret."
  }
  assert {
    condition     = !yamldecode(helm_release.temporal_resources.values[0]).database.caBundle.enabled && length(yamldecode(helm_release.temporal.values[0]).server.additionalVolumes) == 0
    error_message = "Without database TLS, no CA bundle is mounted."
  }
}

run "helm_values_are_applied_last" {
  command = plan

  variables {
    helm_values = ["server:\n  config:\n    logLevel: debug\n"]
  }

  assert {
    condition     = length(helm_release.temporal.values) == 2 && yamldecode(helm_release.temporal.values[1]).server.config.logLevel == "debug"
    error_message = "Extra values documents must follow the module's own."
  }
}

run "rejects_a_mysql_cluster" {
  command = plan

  override_data {
    target = data.aws_rds_cluster.database
    values = {
      engine          = "aurora-mysql"
      endpoint        = "db.cluster-abc123.us-east-2.rds.amazonaws.com"
      port            = 3306
      master_username = "admin"
    }
  }

  expect_failures = [helm_release.temporal_resources]
}

run "requires_a_secret_arn_for_external_secrets" {
  command = plan

  variables {
    database_password_secret_arn = null
  }

  expect_failures = [helm_release.temporal_resources]
}

run "rejects_a_shard_count_that_is_not_a_power_of_two" {
  command = plan

  variables {
    num_history_shards = 500
  }

  expect_failures = [var.num_history_shards]
}

run "rejects_fractional_retention" {
  command = plan

  variables {
    temporal_namespaces = { orders = { retention_days = 1.5 } }
  }

  expect_failures = [var.temporal_namespaces]
}

run "no_namespaces_skips_the_namespace_job" {
  command = plan

  variables {
    temporal_namespaces = {}
  }

  assert {
    condition     = length(yamldecode(helm_release.temporal.values[0]).extraObjects) == 0 && length(output.temporal_namespaces) == 0
    error_message = "With no namespaces, the setup job must not run."
  }
}

################################################################################
# Search attributes
################################################################################

run "search_attributes_are_registered_idempotently_after_each_deploy" {
  command = plan

  variables {
    temporal_namespaces = {
      orders = {
        retention_days    = 30
        search_attributes = { CustomerId = "Keyword", Amount = "Double" }
      }
    }
  }

  assert {
    condition     = yamldecode(yamldecode(helm_release.temporal.values[0]).extraObjects[0]).metadata.annotations["helm.sh/hook"] == "post-install,post-upgrade"
    error_message = "The setup job must run after every install and upgrade."
  }
  assert {
    condition = alltrue([for line in [
      "temporal operator namespace describe -n 'orders' >/dev/null 2>&1 || temporal operator namespace create -n 'orders' --retention 30d",
      "temporal operator namespace update -n 'orders' --retention 30d",
      "grep -qw 'CustomerId' || temporal operator search-attribute create -n 'orders' --name 'CustomerId' --type Keyword",
      "grep -qw 'Amount' || temporal operator search-attribute create -n 'orders' --name 'Amount' --type Double",
    ] : strcontains(yamldecode(yamldecode(helm_release.temporal.values[0]).extraObjects[0]).spec.template.spec.containers[0].args[0], line)])
    error_message = "The job must create the namespace, apply retention and register only missing attributes."
  }
  assert {
    condition     = yamldecode(yamldecode(helm_release.temporal.values[0]).extraObjects[0]).spec.template.spec.containers[0].env[0].value == "temporal-frontend.temporal.svc:7233"
    error_message = "Without JWT authorization the job calls the frontend."
  }
}

run "defaults_apply_to_namespaces_without_settings" {
  command = plan

  variables {
    temporal_namespaces = { orders = {} }
  }

  assert {
    condition     = strcontains(yamldecode(helm_release.temporal.values[0]).extraObjects[0], "--retention 7d")
    error_message = "A namespace without settings keeps 7 days and no custom attributes."
  }
}

run "rejects_unknown_search_attribute_types" {
  command = plan

  variables {
    temporal_namespaces = { orders = { search_attributes = { CustomerId = "String" } } }
  }

  expect_failures = [var.temporal_namespaces]
}

run "rejects_more_attributes_than_postgres_visibility_holds" {
  command = plan

  variables {
    temporal_namespaces = { orders = { search_attributes = { A = "Int", B = "Int", C = "Int", D = "Int" } } }
  }

  expect_failures = [var.temporal_namespaces]
}

################################################################################
# Certificate authority
################################################################################

run "tls_from_an_existing_aws_private_ca_issuer" {
  command = plan

  variables {
    tls_enabled   = true
    tls_ca_source = "issuer"
    tls_issuer    = { name = "private-ca", kind = "AWSPCAClusterIssuer", group = "awspca.cert-manager.io" }
  }

  assert {
    condition     = yamldecode(helm_release.temporal_resources.values[0]).tls.caSource == "issuer" && yamldecode(helm_release.temporal_resources.values[0]).tls.issuerRef.kind == "AWSPCAClusterIssuer" && yamldecode(helm_release.temporal_resources.values[0]).tls.issuerRef.group == "awspca.cert-manager.io"
    error_message = "Leaf certificates must come from the given issuer."
  }
  assert {
    condition     = output.tls_ca_source == "issuer" && output.tls_issuer.name == "private-ca" && output.tls_ca_secret_name == "temporal-frontend-tls"
    error_message = "Outputs must name the issuer and where clients find its CA."
  }
}

run "tls_from_an_existing_ca_secret" {
  command = plan

  variables {
    tls_enabled        = true
    tls_ca_source      = "secret"
    tls_ca_secret_name = "corp-ca"
  }

  assert {
    condition     = yamldecode(helm_release.temporal_resources.values[0]).tls.caSecretName == "corp-ca" && output.tls_issuer.kind == "Issuer" && output.tls_issuer.name == "temporal-ca"
    error_message = "The module's Issuer must sign with the existing CA Secret."
  }
}

run "issuer_ca_needs_an_issuer" {
  command = plan

  variables {
    tls_enabled   = true
    tls_ca_source = "issuer"
  }

  expect_failures = [helm_release.temporal_resources]
}

################################################################################
# JWT authorization
################################################################################

run "jwt_auth_with_identity_provider_keys" {
  command = plan

  variables {
    tls_enabled                     = true
    jwt_auth_enabled                = true
    jwt_auth_audience               = "temporal"
    jwt_auth_jwks_urls              = ["https://idp.example.com/.well-known/jwks.json"]
    jwt_auth_permissions_claim_name = "temporal_permissions"
  }

  assert {
    condition = (
      yamldecode(helm_release.temporal.values[0]).server.config.authorization.authorizer == "default" &&
      yamldecode(helm_release.temporal.values[0]).server.config.authorization.claimMapper == "default" &&
      yamldecode(helm_release.temporal.values[0]).server.config.authorization.audience == "temporal" &&
      yamldecode(helm_release.temporal.values[0]).server.config.authorization.permissionsClaimName == "temporal_permissions" &&
      yamldecode(helm_release.temporal.values[0]).server.config.authorization.jwtKeyProvider.keySourceURIs[0] == "https://idp.example.com/.well-known/jwks.json"
    )
    error_message = "The frontend must check tokens with the default claim mapper and authorizer."
  }
  assert {
    condition     = yamldecode(helm_release.temporal.values[0]).server["internal-frontend"].enabled && yamldecode(helm_release.temporal.values[0]).server["internal-frontend"].replicaCount == 2
    error_message = "Temporal's own callers need the internal frontend."
  }
  assert {
    condition     = yamldecode(yamldecode(helm_release.temporal.values[0]).extraObjects[0]).spec.template.spec.containers[0].env[0].value == "temporal-internal-frontend.temporal.svc:7236" && yamldecode(yamldecode(helm_release.temporal.values[0]).extraObjects[0]).spec.template.spec.volumes[0].secret.secretName == "temporal-internode-tls"
    error_message = "The setup job must call the internal frontend with the internode certificate."
  }
  assert {
    condition     = !yamldecode(helm_release.temporal_resources.values[0]).jwks.enabled && output.internal_frontend_address == "temporal-internal-frontend.temporal.svc:7236"
    error_message = "Keys from a URL need no in-cluster key server."
  }
}

run "jwt_auth_with_keys_from_secrets_manager" {
  command = plan

  variables {
    tls_enabled              = true
    jwt_auth_enabled         = true
    jwt_auth_jwks_source     = "secrets_manager"
    jwt_auth_jwks_secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:jwks-AbCdEf"
  }

  assert {
    condition     = yamldecode(helm_release.temporal_resources.values[0]).jwks.enabled && yamldecode(helm_release.temporal_resources.values[0]).jwks.remoteSecretName == "arn:aws:secretsmanager:us-east-2:123456789012:secret:jwks-AbCdEf"
    error_message = "The key set must be synced and served in the namespace."
  }
  assert {
    condition     = yamldecode(helm_release.temporal.values[0]).server.config.authorization.jwtKeyProvider.keySourceURIs == ["http://temporal-jwks.temporal.svc:8080/jwks.json"] && !can(yamldecode(helm_release.temporal.values[0]).server.config.authorization.audience)
    error_message = "The frontend must read only the in-cluster key server, and skip the audience check when none is set."
  }
}

run "jwt_auth_requires_tls" {
  command = plan

  variables {
    jwt_auth_enabled   = true
    jwt_auth_jwks_urls = ["https://idp.example.com/jwks"]
  }

  expect_failures = [helm_release.temporal_resources]
}

run "jwt_auth_requires_keys" {
  command = plan

  variables {
    tls_enabled      = true
    jwt_auth_enabled = true
  }

  expect_failures = [helm_release.temporal_resources]
}

run "web_ui_as_admin_through_the_internal_frontend" {
  command = plan

  variables {
    tls_enabled                   = true
    jwt_auth_enabled              = true
    jwt_auth_jwks_urls            = ["https://idp.example.com/jwks"]
    web_internal_frontend_enabled = true
  }

  assert {
    condition     = yamldecode(helm_release.temporal.values[0]).web.temporalAddress == "temporal-internal-frontend.temporal.svc:7236" && yamldecode(helm_release.temporal.values[0]).web.tls.secretName == "temporal-internode-tls" && yamldecode(helm_release.temporal.values[0]).web.tls.serverName == "temporal-internode.temporal.svc"
    error_message = "The Web UI must reach the internal frontend with the internode certificate."
  }
}

################################################################################
# Frontend customization
################################################################################

run "custom_claim_mapper_hooks" {
  command = plan

  variables {
    server_image       = "registry.example.com/temporal-server:1.32.2-custom"
    frontend_extra_env = { MAPPER_MODE = "groups" }
    frontend_secret_env = {
      MAPPER_TOKEN = { secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:mapper-AbCdEf", property = "token" }
    }
    server_secret_files = { "/etc/mapper/key.json" = { secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:key-AbCdEf" } }
  }

  assert {
    condition     = yamldecode(helm_release.temporal.values[0]).server.image.repository == "registry.example.com/temporal-server" && yamldecode(helm_release.temporal.values[0]).server.image.tag == "1.32.2-custom"
    error_message = "A custom server image must replace the official one."
  }
  assert {
    condition = (
      contains([for e in yamldecode(helm_release.temporal.values[0]).server.frontend.additionalEnv : e.name], "MAPPER_MODE") &&
      one([for e in yamldecode(helm_release.temporal.values[0]).server.frontend.additionalEnv : e.valueFrom.secretKeyRef if e.name == "MAPPER_TOKEN"]).name == "temporal-frontend-env" &&
      length(yamldecode(helm_release.temporal.values[0]).server.history.additionalEnv) == 1
    )
    error_message = "Extra environment must reach the frontend only, secrets through the synced Secret."
  }
  assert {
    condition     = yamldecode(helm_release.temporal_resources.values[0]).frontendEnv.items[0].remoteProperty == "token" && yamldecode(helm_release.temporal_resources.values[0]).serverFiles.items[0].remoteProperty == ""
    error_message = "Secret values must be synced with their JSON keys."
  }
  assert {
    condition     = one([for m in yamldecode(helm_release.temporal.values[0]).server.additionalVolumeMounts : m if m.mountPath == "/etc/mapper/key.json"]).subPath == "file-0"
    error_message = "Secret files must be mounted at their paths."
  }
}

run "rejects_a_variable_set_twice" {
  command = plan

  variables {
    frontend_extra_env  = { TOKEN = "x" }
    frontend_secret_env = { TOKEN = { secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:t-AbCdEf" } }
  }

  expect_failures = [var.frontend_secret_env]
}

################################################################################
# Internal NLB
################################################################################

run "internal_nlb_for_the_frontend" {
  # The NLB is read after the release that creates it, so its name is known
  # only once applied.
  command = apply

  override_data {
    target = data.aws_lb.frontend
    values = { dns_name = "internal-temporal-123.elb.us-east-2.amazonaws.com" }
  }

  override_data {
    target = data.aws_subnet.frontend_nlb
    values = { cidr_block = "10.20.1.0/24" }
  }

  variables {
    frontend_nlb_enabled      = true
    frontend_nlb_subnet_ids   = ["subnet-0a1b2c3d"]
    frontend_nlb_source_cidrs = ["10.30.0.0/16"]
  }

  assert {
    condition     = yamldecode(helm_release.temporal_resources.values[0]).frontendNlb.enabled && yamldecode(helm_release.temporal_resources.values[0]).frontendNlb.name == "test-cluster-temporal" && yamldecode(helm_release.temporal_resources.values[0]).frontendNlb.crossZoneEnabled
    error_message = "The NLB must take a default name and cross-zone balancing."
  }
  assert {
    condition     = toset(yamldecode(helm_release.temporal_resources.values[0]).networkPolicy.frontendClientCidrs) == toset(["10.30.0.0/16", "10.20.1.0/24"])
    error_message = "The network policy must admit the NLB's clients and its health checks."
  }
  assert {
    condition     = output.frontend_nlb_hostname == "internal-temporal-123.elb.us-east-2.amazonaws.com"
    error_message = "The NLB hostname must be an output."
  }
}

run "internal_nlb_needs_source_cidrs" {
  command = plan

  variables {
    frontend_nlb_enabled = true
  }

  expect_failures = [helm_release.temporal_resources]
}

################################################################################
# Tailscale
################################################################################

run "tailscale_frontend_and_web" {
  command = plan

  variables {
    tls_enabled                               = true
    tailscale_frontend_enabled                = true
    tailscale_frontend_tags                   = ["tag:workflows-grpc"]
    tailscale_web_enabled                     = true
    tailscale_web_tags                        = ["tag:workflows-ui"]
    tailscale_tailnet_domain                  = "example-tailnet.ts.net"
    network_policy_frontend_client_namespaces = ["apps"]
  }

  assert {
    condition     = yamldecode(helm_release.temporal_resources.values[0]).tailscale.frontend.hostname == "temporal-frontend" && yamldecode(helm_release.temporal_resources.values[0]).tailscale.web.hostname == "temporal" && yamldecode(helm_release.temporal_resources.values[0]).tailscale.web.tags[0] == "tag:workflows-ui"
    error_message = "Each Tailscale device must take its default name and tags."
  }
  assert {
    condition     = contains(yamldecode(helm_release.temporal_resources.values[0]).networkPolicy.frontendClientNamespaces, "tailscale")
    error_message = "The operator's proxies must be admitted when client namespaces are listed."
  }
  assert {
    condition     = contains(yamldecode(helm_release.temporal_resources.values[0]).tls.frontend.dnsNames, "temporal-frontend.example-tailnet.ts.net")
    error_message = "The frontend certificate must cover its tailnet name."
  }
  assert {
    condition     = output.tailscale_frontend_address == "temporal-frontend.example-tailnet.ts.net:7233" && output.tailscale_web_url == "https://temporal.example-tailnet.ts.net"
    error_message = "Outputs must give the tailnet addresses."
  }
}

################################################################################
# Web UI sign-in
################################################################################

run "google_sign_in_on_the_tailnet" {
  command = plan

  variables {
    tailscale_web_enabled      = true
    tailscale_tailnet_domain   = "example-tailnet.ts.net"
    web_oidc_enabled           = true
    web_oidc_client_secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:oidc-AbCdEf"
  }

  assert {
    condition = alltrue([for e in [
      { name = "TEMPORAL_AUTH_ENABLED", value = "true" },
      { name = "TEMPORAL_AUTH_PROVIDER_URL", value = "https://accounts.google.com" },
      { name = "TEMPORAL_AUTH_CALLBACK_URL", value = "https://temporal.example-tailnet.ts.net/auth/sso/callback" },
      { name = "TEMPORAL_AUTH_SCOPES", value = "openid,profile,email" },
    ] : contains(yamldecode(helm_release.temporal.values[0]).web.additionalEnv, e)])
    error_message = "The Google preset must fill the issuer and scopes, and the callback must follow the tailnet host."
  }
  assert {
    condition     = yamldecode(helm_release.temporal.values[0]).web.additionalEnvSecretName == "temporal-web-oidc" && yamldecode(helm_release.temporal_resources.values[0]).webOidc.clientIdProperty == "client_id"
    error_message = "The client ID and secret must come from the synced Secret."
  }
  assert {
    condition     = !contains([for e in yamldecode(helm_release.temporal.values[0]).web.additionalEnv : e.name], "TEMPORAL_AUTH_USE_ID_TOKEN_AS_BEARER")
    error_message = "Without JWT authorization the UI must not forward ID tokens."
  }
  assert {
    condition     = output.web_oidc_callback_url == "https://temporal.example-tailnet.ts.net/auth/sso/callback"
    error_message = "The callback URL to register must be an output."
  }
}

run "okta_sign_in_forwards_id_tokens_to_the_authorizer" {
  command = plan

  variables {
    tls_enabled                 = true
    jwt_auth_enabled            = true
    jwt_auth_jwks_urls          = ["https://example.okta.com/oauth2/v1/keys"]
    web_ingress_enabled         = true
    web_ingress_host            = "temporal.internal.example.com"
    web_ingress_certificate_arn = "arn:aws:acm:us-east-2:123456789012:certificate/abc"
    web_oidc_enabled            = true
    web_oidc_provider           = "okta"
    web_oidc_issuer_url         = "https://example.okta.com"
    web_oidc_client_secret_arn  = "arn:aws:secretsmanager:us-east-2:123456789012:secret:oidc-AbCdEf"
  }

  assert {
    condition = alltrue([for e in [
      { name = "TEMPORAL_AUTH_ISSUER_URL", value = "https://example.okta.com" },
      { name = "TEMPORAL_AUTH_CALLBACK_URL", value = "https://temporal.internal.example.com/auth/sso/callback" },
      { name = "TEMPORAL_AUTH_SCOPES", value = "openid,profile,email,offline_access" },
      { name = "TEMPORAL_AUTH_USE_ID_TOKEN_AS_BEARER", value = "true" },
    ] : contains(yamldecode(helm_release.temporal.values[0]).web.additionalEnv, e)])
    error_message = "With the authorizer on, the UI must forward each user's ID token."
  }
}

run "okta_needs_an_issuer" {
  command = plan

  variables {
    tailscale_web_enabled      = true
    tailscale_tailnet_domain   = "example-tailnet.ts.net"
    web_oidc_enabled           = true
    web_oidc_provider          = "okta"
    web_oidc_client_secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:oidc-AbCdEf"
  }

  expect_failures = [helm_release.temporal_resources]
}

run "sign_in_needs_a_callback_url" {
  command = plan

  variables {
    web_oidc_enabled           = true
    web_oidc_client_secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:oidc-AbCdEf"
  }

  expect_failures = [helm_release.temporal_resources]
}
