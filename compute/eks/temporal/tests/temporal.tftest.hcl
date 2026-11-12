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
    condition     = yamldecode(helm_release.temporal.values[0]).server.config.namespaces.create && yamldecode(helm_release.temporal.values[0]).server.config.namespaces.namespace[0].name == "default" && yamldecode(helm_release.temporal.values[0]).server.config.namespaces.namespace[0].retention == "7d"
    error_message = "The default Temporal namespace must be created with 7 days of retention."
  }
  assert {
    condition = (
      yamldecode(helm_release.temporal_resources.values[0]).database.externalSecret.enabled &&
      yamldecode(helm_release.temporal_resources.values[0]).database.externalSecret.remoteSecretName == "arn:aws:secretsmanager:us-east-2:123456789012:secret:temporal-db-AbCdEf" &&
      yamldecode(helm_release.temporal_resources.values[0]).database.externalSecret.secretStoreName == "ravion-aws" &&
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
    temporal_namespaces = { orders = 1.5 }
  }

  expect_failures = [var.temporal_namespaces]
}

run "no_namespaces_skips_the_namespace_job" {
  command = plan

  variables {
    temporal_namespaces = {}
  }

  assert {
    condition     = !yamldecode(helm_release.temporal.values[0]).server.config.namespaces.create && length(output.temporal_namespaces) == 0
    error_message = "With no namespaces, the namespace job must not run."
  }
}
