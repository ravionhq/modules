mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-2" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:us-east-2:123456789012:cluster/test-cluster"
      endpoint              = "https://mock.eks.amazonaws.com"
      certificate_authority = [{ data = "bW9jay1jYQ==" }]
    }
  }
  mock_data "aws_s3_bucket" {
    defaults = {
      arn           = "arn:aws:s3:::existing-bucket"
      bucket_region = "us-west-2"
    }
  }
  mock_resource "aws_s3_bucket" {
    defaults = {
      arn    = "arn:aws:s3:::analytics-clickhouse-abc123"
      bucket = "analytics-clickhouse-abc123"
    }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/analytics-clickhouse-1" }
  }
  mock_resource "aws_secretsmanager_secret" {
    defaults = { arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:mock-AbCdEf" }
  }
}
mock_provider "helm" {}

variables {
  cluster_name = "test-cluster"
  region       = "us-east-2"
  name         = "analytics"
  namespace    = "analytics"
}

run "defaults_install_a_replicated_cluster_with_backups_and_a_cold_tier" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket.this) == 1 && aws_s3_bucket.this[0].bucket_prefix == "analytics-clickhouse-" && !aws_s3_bucket.this[0].force_destroy
    error_message = "The module must create a retained bucket named after the installation by default."
  }
  assert {
    condition     = aws_s3_bucket_versioning.this[0].versioning_configuration[0].status == "Enabled" && aws_s3_bucket_public_access_block.this[0].block_public_acls && aws_s3_bucket_public_access_block.this[0].restrict_public_buckets
    error_message = "The bucket must be versioned and private."
  }
  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this[0].rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256"
    error_message = "Without a KMS key the bucket must default to SSE-S3."
  }
  assert {
    condition     = aws_eks_pod_identity_association.clickhouse[0].namespace == "analytics" && aws_eks_pod_identity_association.clickhouse[0].service_account == "analytics-clickhouse"
    error_message = "The S3 role must be bound to the ClickHouse ServiceAccount in the installation's namespace."
  }
  assert {
    condition     = toset(keys(aws_secretsmanager_secret.user)) == toset(["admin", "writer", "reader", "operator"])
    error_message = "One credential secret per user must be created."
  }
  assert {
    condition     = aws_secretsmanager_secret.user["reader"].name == "clickhouse/test-cluster/analytics/analytics/reader"
    error_message = "Secret names must default to clickhouse/<cluster>/<namespace>/<name>/<user>."
  }
  assert {
    condition     = aws_secretsmanager_secret_version.password["admin"].secret_string_wo_version == 1 && aws_secretsmanager_secret.password["admin"].name == "clickhouse/test-cluster/analytics/analytics/admin-password"
    error_message = "Passwords must be written through the write-only argument to their own secret, versioned by password_version."
  }
  assert {
    condition     = aws_secretsmanager_secret_version.user["admin"].secret_string_wo_version == parseint(substr(sha256(jsonencode({ password_version = 1, tls_enabled = true, plaintext_ports_open = false, database = "default" })), 0, 7), 16)
    error_message = "The connection details must be versioned by password_version and the TLS settings."
  }
  assert {
    condition     = helm_release.secrets.name == "analytics-secrets" && helm_release.operator.name == "analytics-operator" && helm_release.cluster.name == "analytics"
    error_message = "The three releases must be named after the installation."
  }
  assert {
    condition     = helm_release.operator.repository == "https://helm.altinity.com" && helm_release.operator.chart == "altinity-clickhouse-operator" && helm_release.operator.version == "0.27.4"
    error_message = "The operator must come from the pinned upstream chart."
  }
  assert {
    condition     = output.host == "clickhouse-analytics.analytics.svc.cluster.local" && output.https_endpoint == "https://clickhouse-analytics.analytics.svc.cluster.local:8443" && output.cluster == "main"
    error_message = "Connection outputs must point at the installation's Service."
  }
  assert {
    condition     = output.cold_storage_policy == "tiered" && output.backup_enabled
    error_message = "Backups and the cold tier must be on by default."
  }
}

run "operator_watches_only_its_namespace_and_waits_for_its_credentials" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.operator.values[0]).watchNamespaces == ["analytics"] && yamldecode(helm_release.operator.values[0]).rbac.namespaceScoped
    error_message = "The operator must watch only the installation's namespace with namespaced RBAC."
  }
  assert {
    condition     = yamldecode(helm_release.operator.values[0]).fullnameOverride == "analytics-operator" && !yamldecode(helm_release.operator.values[0]).secret.create
    error_message = "The operator's credentials Secret must come from External Secrets, named after the operator release."
  }
  assert {
    condition     = one(yamldecode(helm_release.operator.values[0]).operator.env).valueFrom.secretKeyRef.name == "analytics-operator"
    error_message = "The operator container must reference its credentials Secret so it never starts without it."
  }
  assert {
    condition     = yamldecode(helm_release.operator.values[0]).crdHook.enabled
    error_message = "CRD management must be on by default."
  }
}

run "no_password_reaches_helm_values" {
  command = plan

  assert {
    condition = alltrue([
      for release in [helm_release.secrets, helm_release.operator, helm_release.cluster] :
      !can(regex("\"password\"\\s*:\\s*\"", jsonencode(yamldecode(release.values[0]))))
    ])
    error_message = "No release may carry a password value."
  }
  assert {
    condition     = [for secret in yamldecode(helm_release.secrets.values[0]).secrets : secret.name] == ["analytics-admin", "analytics-operator", "analytics-reader", "analytics-writer"]
    error_message = "Every user, including the operator, must have an ExternalSecret."
  }
  assert {
    condition     = yamldecode(helm_release.secrets.values[0]).store.create && yamldecode(helm_release.secrets.values[0]).store.kind == "SecretStore"
    error_message = "Without a named ClusterSecretStore the module must create a namespaced SecretStore."
  }
}

run "an_existing_cluster_secret_store_is_used_as_is" {
  command = plan

  variables {
    external_secrets = { cluster_secret_store_name = "shared-aws" }
  }

  assert {
    condition     = !yamldecode(helm_release.secrets.values[0]).store.create && yamldecode(helm_release.secrets.values[0]).store.kind == "ClusterSecretStore" && yamldecode(helm_release.secrets.values[0]).store.name == "shared-aws"
    error_message = "A named ClusterSecretStore must be referenced, not created."
  }
}

run "without_backups_or_cold_tier_no_aws_storage_is_created" {
  command = plan

  variables {
    backup_enabled       = false
    cold_storage_enabled = false
  }

  assert {
    condition     = length(aws_s3_bucket.this) == 0 && length(aws_iam_role.clickhouse) == 0 && length(aws_eks_pod_identity_association.clickhouse) == 0
    error_message = "No bucket, role or association may exist when nothing uses S3."
  }
  assert {
    condition     = yamldecode(helm_release.cluster.values[0]).s3.bucket == "" && output.s3_bucket_name == null && output.iam_role_arn == null && output.cold_storage_policy == null
    error_message = "The cluster chart and outputs must see no bucket."
  }
}

run "an_existing_bucket_is_used_instead_of_creating_one" {
  command = plan

  variables {
    s3_bucket_creation_enabled = false
    s3_bucket_name             = "existing-bucket"
  }

  assert {
    condition     = length(aws_s3_bucket.this) == 0 && length(aws_s3_bucket_policy.this) == 0
    error_message = "An existing bucket must not be created or have its policy replaced."
  }
  assert {
    condition     = yamldecode(helm_release.cluster.values[0]).s3.bucket == "existing-bucket" && yamldecode(helm_release.cluster.values[0]).s3.region == "us-west-2"
    error_message = "The cluster chart must use the existing bucket and its own region."
  }
}

run "a_kms_key_encrypts_the_bucket_and_is_granted_to_the_role" {
  command = plan

  variables {
    s3_kms_key_arn = "arn:aws:kms:us-east-2:123456789012:key/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this[0].rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    error_message = "A KMS key must switch the bucket to SSE-KMS."
  }
}

run "layout_and_sizing_reach_the_cluster_chart" {
  command = plan

  variables {
    shard_count            = 2
    replica_count          = 3
    keeper_replica_count   = 5
    clickhouse_volume_size = "500Gi"
    clickhouse_resources   = { cpu_request = "4", memory_request = "32Gi", memory_limit = "32Gi" }
    database_name          = "events"
    zone_spread            = "required"
  }

  assert {
    condition     = yamldecode(helm_release.cluster.values[0]).clickhouse.shards == 2 && yamldecode(helm_release.cluster.values[0]).clickhouse.replicas == 3 && yamldecode(helm_release.cluster.values[0]).keeper.replicas == 5
    error_message = "Shards, replicas and Keeper nodes must reach the chart."
  }
  assert {
    condition     = yamldecode(helm_release.cluster.values[0]).clickhouse.volumeSize == "500Gi" && yamldecode(helm_release.cluster.values[0]).clickhouse.resources.limits.memory == "32Gi" && !contains(keys(yamldecode(helm_release.cluster.values[0]).clickhouse.resources.limits), "cpu")
    error_message = "Sizing must reach the chart, with no CPU limit unless one is set."
  }
  assert {
    condition     = yamldecode(helm_release.cluster.values[0]).database.name == "events" && yamldecode(helm_release.cluster.values[0]).placement.zoneSpread == "required" && output.database == "events"
    error_message = "The database and zone spread must reach the chart."
  }
}

run "a_dedicated_node_pool_adds_its_toleration" {
  command = plan

  variables {
    dedicated_node_pool = { enabled = true, architectures = ["arm64"] }
    priority_class      = { enabled = true }
  }

  assert {
    condition     = yamldecode(helm_release.cluster.values[0]).placement.nodePool.create && yamldecode(helm_release.cluster.values[0]).placement.nodePool.architectures == ["arm64"]
    error_message = "The node pool must be created with the chosen architectures."
  }
  assert {
    condition     = one(yamldecode(helm_release.cluster.values[0]).placement.tolerations).key == "clickhouse.ravion.com/dedicated" && one(yamldecode(helm_release.cluster.values[0]).placement.tolerations).value == "analytics"
    error_message = "Pods must tolerate the dedicated pool's taint."
  }
  assert {
    condition     = yamldecode(helm_release.cluster.values[0]).placement.priorityClass.create && yamldecode(helm_release.cluster.values[0]).placement.priorityClass.name == "analytics-analytics-clickhouse"
    error_message = "The PriorityClass must be named after the namespace and installation."
  }
}

run "rotating_passwords_bumps_the_secret_version_and_restarts_pods" {
  command = plan

  variables {
    password_version = 2
  }

  assert {
    condition     = aws_secretsmanager_secret_version.password["writer"].secret_string_wo_version == 2 && aws_secretsmanager_secret_version.user["writer"].secret_string_wo_version == parseint(substr(sha256(jsonencode({ password_version = 2, tls_enabled = true, plaintext_ports_open = false, database = "default" })), 0, 7), 16)
    error_message = "A new password_version must write new passwords and rewrite the connection details."
  }
  assert {
    condition     = yamldecode(helm_release.cluster.values[0]).passwordAnnotations["clickhouse.ravion.com/password-version"] == "2" && yamldecode(helm_release.operator.values[0]).podAnnotations["clickhouse.ravion.com/password-version"] == "2" && yamldecode(helm_release.secrets.values[0]).passwordVersion == tostring(parseint(substr(sha256(jsonencode({ password_version = 2, tls_enabled = true, plaintext_ports_open = false, database = "default" })), 0, 7), 16))
    error_message = "A new password_version must refresh the secrets and restart ClickHouse and the operator."
  }
}

run "changing_the_database_rewrites_the_connection_details_but_not_the_passwords" {
  command = plan

  variables {
    database_name = "events"
  }

  assert {
    condition     = aws_secretsmanager_secret_version.user["writer"].secret_string_wo_version == parseint(substr(sha256(jsonencode({ password_version = 1, tls_enabled = true, plaintext_ports_open = false, database = "events" })), 0, 7), 16) && aws_secretsmanager_secret_version.user["writer"].secret_string_wo_version != parseint(substr(sha256(jsonencode({ password_version = 1, tls_enabled = true, plaintext_ports_open = false, database = "default" })), 0, 7), 16)
    error_message = "A database change must rewrite the connection details."
  }
  assert {
    condition     = aws_secretsmanager_secret_version.password["writer"].secret_string_wo_version == 1 && yamldecode(helm_release.cluster.values[0]).passwordAnnotations["clickhouse.ravion.com/password-version"] == "1"
    error_message = "A database change must not write new passwords or restart for one."
  }
}

run "the_secrets_release_waits_for_the_synced_version" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.secrets.values[0]).syncWait.timeoutSeconds == 1800 && yamldecode(helm_release.secrets.values[0]).passwordVersion == tostring(parseint(substr(sha256(jsonencode({ password_version = 1, tls_enabled = true, plaintext_ports_open = false, database = "default" })), 0, 7), 16))
    error_message = "The secrets release must wait, within the Helm timeout, for the version the connection details are written with."
  }
}

run "backups_are_bounded_and_kept_apart_per_installation" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.cluster.values[0]).backup.pathPrefix == "analytics/analytics" && yamldecode(helm_release.cluster.values[0]).backup.timeoutSeconds == 21600
    error_message = "Backups must default to a <namespace>/<name> prefix and a six-hour limit."
  }
}

run "a_backup_path_prefix_and_timeout_reach_the_chart" {
  command = plan

  variables {
    backup_path_prefix     = "team-a/analytics"
    backup_timeout_seconds = 3600
  }

  assert {
    condition     = yamldecode(helm_release.cluster.values[0]).backup.pathPrefix == "team-a/analytics" && yamldecode(helm_release.cluster.values[0]).backup.timeoutSeconds == 3600
    error_message = "backup_path_prefix and backup_timeout_seconds must reach the chart."
  }
}

run "invalid_backup_path_prefix_is_rejected" {
  command = plan

  variables {
    backup_path_prefix = "/team a/"
  }

  expect_failures = [var.backup_path_prefix]
}

run "short_backup_timeout_is_rejected" {
  command = plan

  variables {
    backup_timeout_seconds = 60
  }

  expect_failures = [var.backup_timeout_seconds]
}

run "node_spread_defaults_to_preferred" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.cluster.values[0]).placement.nodeSpread == "preferred" && yamldecode(helm_release.cluster.values[0]).placement.zoneSpread == "preferred"
    error_message = "Node and zone spread must default to preferred, so the defaults fit a two-node cluster."
  }
}

run "required_node_spread_reaches_the_chart" {
  command = plan

  variables {
    node_spread = "required"
  }

  assert {
    condition     = yamldecode(helm_release.cluster.values[0]).placement.nodeSpread == "required"
    error_message = "node_spread must reach the chart."
  }
}

run "unknown_node_spread_is_rejected" {
  command = plan

  variables {
    node_spread = "strict"
  }

  expect_failures = [var.node_spread]
}

run "metrics_options_reach_the_cluster_chart" {
  command = plan

  variables {
    metrics_pod_monitors_enabled = true
    metrics_otlp_endpoint        = "http://otel.monitoring.svc.cluster.local:4318"
  }

  assert {
    condition     = yamldecode(helm_release.cluster.values[0]).metrics.podMonitors.enabled && yamldecode(helm_release.cluster.values[0]).metrics.otlp.endpoint == "http://otel.monitoring.svc.cluster.local:4318"
    error_message = "PodMonitors and the OTLP push must reach the chart."
  }
  assert {
    condition     = !yamldecode(helm_release.operator.values[0]).metrics.enabled && yamldecode(helm_release.operator.values[0]).podAnnotations["prometheus.io/port"] == "9999"
    error_message = "The operator must not duplicate server metrics and must expose its own."
  }
}

run "tls_is_on_by_default" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.cluster.values[0]).tls.enabled && yamldecode(helm_release.cluster.values[0]).tls.disablePlaintextPorts && yamldecode(helm_release.cluster.values[0]).tls.internal && yamldecode(helm_release.secrets.values[0]).tls.enabled && yamldecode(helm_release.secrets.values[0]).tls.caSource == "self_signed"
    error_message = "TLS, closed plaintext ports and internal TLS must be on by default, from a self-signed CA."
  }
  assert {
    condition     = output.https_port == 8443 && output.secure_native_port == 9440 && output.http_port == null && output.native_port == null && output.tls_ca_secret_name == "analytics-server-tls"
    error_message = "By default only the TLS ports are output."
  }
  assert {
    condition     = yamldecode(helm_release.operator.values[0]).configs.files["config.yaml"].clickhouse.access.scheme == "https"
    error_message = "By default the operator uses HTTPS."
  }
}

run "tls_off" {
  command = plan

  variables {
    tls_enabled = false
  }

  assert {
    condition     = !yamldecode(helm_release.cluster.values[0]).tls.enabled && !yamldecode(helm_release.cluster.values[0]).tls.disablePlaintextPorts && !yamldecode(helm_release.cluster.values[0]).tls.internal && !yamldecode(helm_release.secrets.values[0]).tls.enabled
    error_message = "Turning TLS off must turn off the plaintext port closing and internal TLS with it."
  }
  assert {
    condition     = output.tls_ca_secret_name == null && output.https_port == null && output.native_port == 9000 && output.http_port == 8123
    error_message = "Without TLS only the plaintext ports are output."
  }
  assert {
    condition     = yamldecode(helm_release.operator.values[0]).configs.files["config.yaml"].clickhouse.access.scheme == "Auto"
    error_message = "Without TLS the operator keeps choosing the scheme itself."
  }
  assert {
    condition     = aws_secretsmanager_secret_version.user["admin"].secret_string_wo_version == parseint(substr(sha256(jsonencode({ password_version = 1, tls_enabled = false, plaintext_ports_open = true, database = "default" })), 0, 7), 16) && aws_secretsmanager_secret_version.password["admin"].secret_string_wo_version == 1
    error_message = "Turning TLS off rewrites the connection details but not the passwords."
  }
}

run "tls_with_a_self_signed_ca" {
  command = plan

  variables {
    tls_enabled                 = true
    tls_disable_plaintext_ports = false
    tls_internal_enabled        = false
    tls_extra_dns_names         = ["clickhouse.example.internal"]
  }

  assert {
    condition     = yamldecode(helm_release.cluster.values[0]).tls.enabled && !yamldecode(helm_release.cluster.values[0]).tls.disablePlaintextPorts && !yamldecode(helm_release.cluster.values[0]).tls.internal && yamldecode(helm_release.cluster.values[0]).tls.serverSecretName == "analytics-server-tls"
    error_message = "TLS must reach the cluster chart with the plaintext ports still open and internal TLS off."
  }
  assert {
    condition     = yamldecode(helm_release.secrets.values[0]).tls.enabled && yamldecode(helm_release.secrets.values[0]).tls.caSource == "self_signed" && yamldecode(helm_release.secrets.values[0]).tls.issuerName == "analytics-ca" && yamldecode(helm_release.secrets.values[0]).tls.caSecretName == "analytics-ca" && yamldecode(helm_release.secrets.values[0]).tls.serverSecretName == "analytics-server-tls"
    error_message = "The certificate must be created by the first release, from a CA named after the installation."
  }
  assert {
    condition     = yamldecode(helm_release.secrets.values[0]).tls.dnsNames[0] == "clickhouse-analytics.analytics.svc.cluster.local" && contains(yamldecode(helm_release.secrets.values[0]).tls.dnsNames, "chi-analytics-main-0-1.analytics.svc.cluster.local") && contains(yamldecode(helm_release.secrets.values[0]).tls.dnsNames, "chi-analytics-main-0-1-0.chi-analytics-main-0-1.analytics.svc.cluster.local") && contains(yamldecode(helm_release.secrets.values[0]).tls.dnsNames, "localhost") && contains(yamldecode(helm_release.secrets.values[0]).tls.dnsNames, "clickhouse.example.internal")
    error_message = "The certificate must name the Service, every replica's Service and pod, localhost and the extra names."
  }
  assert {
    condition     = length(yamldecode(helm_release.secrets.values[0]).tls.dnsNames) == 16 && !contains(yamldecode(helm_release.secrets.values[0]).tls.dnsNames, "keeper-analytics-keeper")
    error_message = "Without internal TLS the certificate must not name Keeper."
  }
  assert {
    condition     = yamldecode(helm_release.operator.values[0]).configs.files["config.yaml"].clickhouse.access.scheme == "https"
    error_message = "With TLS the operator must always use HTTPS."
  }
  assert {
    condition     = output.tls_enabled && output.https_port == 8443 && output.secure_native_port == 9440 && output.native_port == 9000 && output.http_port == 8123
    error_message = "TLS adds the secure ports beside the plaintext ones."
  }
  assert {
    condition     = output.tls_server_name == "clickhouse-analytics.analytics.svc.cluster.local" && output.tls_ca_secret_name == "analytics-server-tls" && output.tls_ca_source == "self_signed"
    error_message = "Clients must verify the Service name and trust the server certificate Secret's ca.crt."
  }
  assert {
    condition     = output.tls_issuer.name == "analytics-ca" && output.tls_issuer.kind == "Issuer" && output.tls_issuer.group == "cert-manager.io"
    error_message = "The module's own CA Issuer must sign the server certificate."
  }
  assert {
    condition     = aws_secretsmanager_secret_version.user["writer"].secret_string_wo_version == parseint(substr(sha256(jsonencode({ password_version = 1, tls_enabled = true, plaintext_ports_open = true, database = "default" })), 0, 7), 16) && aws_secretsmanager_secret_version.password["writer"].secret_string_wo_version == 1
    error_message = "Turning TLS on must rewrite the connection details but not the passwords."
  }
  assert {
    condition     = yamldecode(helm_release.secrets.values[0]).passwordVersion == tostring(parseint(substr(sha256(jsonencode({ password_version = 1, tls_enabled = true, plaintext_ports_open = true, database = "default" })), 0, 7), 16)) && yamldecode(helm_release.cluster.values[0]).passwordAnnotations["clickhouse.ravion.com/password-version"] == "1"
    error_message = "Turning TLS on must refresh the Kubernetes Secrets without restarting for a password change."
  }
}

run "tls_with_an_existing_issuer" {
  command = plan

  variables {
    tls_enabled   = true
    tls_ca_source = "issuer"
    tls_issuer = {
      name  = "private-ca"
      kind  = "AWSPCAClusterIssuer"
      group = "awspca.cert-manager.io"
    }
  }

  assert {
    condition     = yamldecode(helm_release.secrets.values[0]).tls.caSource == "issuer" && yamldecode(helm_release.secrets.values[0]).tls.issuerRef.name == "private-ca" && yamldecode(helm_release.secrets.values[0]).tls.issuerRef.kind == "AWSPCAClusterIssuer" && yamldecode(helm_release.secrets.values[0]).tls.issuerRef.group == "awspca.cert-manager.io"
    error_message = "An existing issuer must reach the chart as is."
  }
  assert {
    condition     = output.tls_ca_source == "issuer" && output.tls_issuer.name == "private-ca" && output.tls_issuer.kind == "AWSPCAClusterIssuer"
    error_message = "The outputs must name the existing issuer."
  }
}

run "tls_issuer_kind_and_group_default_to_a_cert_manager_cluster_issuer" {
  command = plan

  variables {
    tls_enabled   = true
    tls_ca_source = "issuer"
    tls_issuer    = { name = "corp-ca" }
  }

  assert {
    condition     = output.tls_issuer.kind == "ClusterIssuer" && output.tls_issuer.group == "cert-manager.io"
    error_message = "tls_issuer kind and group must default to a cert-manager ClusterIssuer."
  }
}

run "tls_with_an_existing_ca_secret" {
  command = plan

  variables {
    tls_enabled        = true
    tls_ca_source      = "secret"
    tls_ca_secret_name = "corp-ca"
  }

  assert {
    condition     = yamldecode(helm_release.secrets.values[0]).tls.caSource == "secret" && yamldecode(helm_release.secrets.values[0]).tls.caSecretName == "corp-ca" && yamldecode(helm_release.secrets.values[0]).tls.issuerRef.name == "analytics-ca"
    error_message = "The module's CA Issuer must sign with the existing CA secret."
  }
  assert {
    condition     = output.tls_ca_source == "secret" && output.tls_ca_secret_name == "analytics-server-tls"
    error_message = "Clients still trust the server certificate Secret's ca.crt."
  }
}

run "tls_with_plaintext_ports_closed" {
  command = plan

  variables {
    tls_enabled                 = true
    tls_disable_plaintext_ports = true
  }

  assert {
    condition     = yamldecode(helm_release.cluster.values[0]).tls.disablePlaintextPorts
    error_message = "Closing the plaintext ports must reach the chart."
  }
  assert {
    condition     = output.http_port == null && output.native_port == null && output.http_endpoint == null && output.https_endpoint == "https://clickhouse-analytics.analytics.svc.cluster.local:8443"
    error_message = "With the plaintext ports closed, only the TLS endpoints are output."
  }
  assert {
    condition     = aws_secretsmanager_secret_version.user["reader"].secret_string_wo_version == parseint(substr(sha256(jsonencode({ password_version = 1, tls_enabled = true, plaintext_ports_open = false, database = "default" })), 0, 7), 16) && aws_secretsmanager_secret_version.password["reader"].secret_string_wo_version == 1
    error_message = "Closing the plaintext ports must rewrite the connection details but not the passwords."
  }
}

run "tls_internal_names_keeper_on_the_certificate" {
  command = plan

  variables {
    tls_enabled          = true
    tls_internal_enabled = true
  }

  assert {
    condition     = yamldecode(helm_release.cluster.values[0]).tls.internal
    error_message = "Internal TLS must reach the cluster chart."
  }
  assert {
    condition     = contains(yamldecode(helm_release.secrets.values[0]).tls.dnsNames, "keeper-analytics-keeper.analytics.svc.cluster.local") && contains(yamldecode(helm_release.secrets.values[0]).tls.dnsNames, "chk-analytics-keeper-keeper-0-2.analytics.svc.cluster.local") && contains(yamldecode(helm_release.secrets.values[0]).tls.dnsNames, "chk-analytics-keeper-keeper-0-2-client")
    error_message = "With internal TLS the certificate must name the Keeper Service and every Keeper node's Services."
  }
  assert {
    condition     = aws_secretsmanager_secret_version.user["admin"].secret_string_wo_version == parseint(substr(sha256(jsonencode({ password_version = 1, tls_enabled = true, plaintext_ports_open = false, database = "default" })), 0, 7), 16)
    error_message = "Internal TLS does not change the client ports, so the connection details keep their version."
  }
}

run "tls_issuer_source_needs_an_issuer" {
  command = plan

  variables {
    tls_enabled   = true
    tls_ca_source = "issuer"
  }

  expect_failures = [helm_release.secrets]
}

run "tls_secret_source_needs_a_secret_name" {
  command = plan

  variables {
    tls_enabled   = true
    tls_ca_source = "secret"
  }

  expect_failures = [helm_release.secrets]
}

run "unknown_tls_ca_source_is_rejected" {
  command = plan

  variables {
    tls_ca_source = "acme"
  }

  expect_failures = [var.tls_ca_source]
}

run "invalid_tls_issuer_is_rejected" {
  command = plan

  variables {
    tls_issuer = { name = "Private_CA", kind = "clusterissuer" }
  }

  expect_failures = [var.tls_issuer]
}

run "invalid_tls_extra_dns_name_is_rejected" {
  command = plan

  variables {
    tls_extra_dns_names = ["not a name"]
  }

  expect_failures = [var.tls_extra_dns_names]
}

run "invalid_name_is_rejected" {
  command = plan

  variables {
    name = "Analytics_Cluster"
  }

  expect_failures = [var.name]
}

run "even_keeper_count_is_rejected" {
  command = plan

  variables {
    keeper_replica_count = 2
  }

  expect_failures = [var.keeper_replica_count]
}

run "built_in_database_is_rejected" {
  command = plan

  variables {
    database_name = "system"
  }

  expect_failures = [var.database_name]
}
