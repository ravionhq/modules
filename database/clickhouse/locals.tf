locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "database/clickhouse"
  }
  tags = merge(local.default_tags, var.tags)

  region     = data.aws_region.current.region
  account_id = data.aws_caller_identity.current.account_id

  # The ClickHouse cluster inside the installation, as named in ON CLUSTER.
  cluster_layout_name = "main"

  # Every installation runs its own operator release; its fullname prefixes the
  # operator's cluster-scoped objects (the CRD install hook's ClusterRole), so
  # two installations on one cluster never collide. The operator also reads its
  # ClickHouse credentials from a Secret of exactly this name.
  operator_fullname = "${var.name}-operator"

  service_account_name = "${var.name}-clickhouse"

  # Service the operator creates for the whole installation (see the cluster
  # chart's serviceTemplate).
  service_host = "clickhouse-${var.name}.${var.namespace}.svc.cluster.local"

  ################################################################################
  # TLS
  ################################################################################

  plaintext_ports_open = !(var.tls_enabled && var.tls_disable_plaintext_ports)

  # Server certificate. Its ca.crt is the CA clients trust, whichever CA
  # issued it.
  tls_server_secret = "${var.name}-server-tls"

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

  tls_internal = var.tls_enabled && var.tls_internal_enabled

  # Version of the connection details written to each user secret: changes
  # with password_version and with every other value in them (the ports and
  # the database), never otherwise. Write-only contents cannot trigger a write
  # on their own, so everything they hold besides the password goes in here.
  connection_details = {
    password_version     = var.password_version
    tls_enabled          = var.tls_enabled
    plaintext_ports_open = local.plaintext_ports_open
    database             = coalesce(var.database_name, "default")
  }
  connection_version = parseint(substr(sha256(jsonencode(local.connection_details)), 0, 7), 16)

  # Every name the server certificate covers, each in its short, namespace,
  # svc and cluster-local forms: the installation's Service (first, as the
  # common name), each replica's Service (what remote_servers, the operator,
  # the backup job and interserver HTTPS use) and pod, localhost for the
  # backup sidecar, and with internal TLS each Keeper node's Services.
  keeper_installation = "${var.name}-keeper"
  tls_hosts = concat(
    ["clickhouse-${var.name}"],
    flatten([for s in range(var.shard_count) : [for r in range(var.replica_count) : "chi-${var.name}-${local.cluster_layout_name}-${s}-${r}"]]),
    local.tls_internal ? concat(
      ["keeper-${local.keeper_installation}"],
      flatten([for r in range(var.keeper_replica_count) : ["chk-${local.keeper_installation}-keeper-0-${r}", "chk-${local.keeper_installation}-keeper-0-${r}-client"]]),
    ) : [],
  )
  tls_dns_names = distinct(concat(
    flatten([for h in local.tls_hosts : ["${h}.${var.namespace}.svc.cluster.local", "${h}.${var.namespace}.svc", "${h}.${var.namespace}", h]]),
    flatten([for s in range(var.shard_count) : [for r in range(var.replica_count) : "chi-${var.name}-${local.cluster_layout_name}-${s}-${r}-0.chi-${var.name}-${local.cluster_layout_name}-${s}-${r}.${var.namespace}.svc.cluster.local"]]),
    ["localhost"],
    var.tls_extra_dns_names,
  ))

  ################################################################################
  # Users
  ################################################################################

  secrets_name_prefix = coalesce(var.secrets_name_prefix, "clickhouse/${var.cluster_name}/${var.namespace}/${var.name}")

  # username is what clients log in as; secret is the in-cluster Secret the
  # External Secrets Operator writes. The operator's own user is read by the
  # operator, which looks for a Secret named after its release.
  users = {
    admin = {
      username = "admin"
      secret   = "${var.name}-admin"
    }
    writer = {
      username = "writer"
      secret   = "${var.name}-writer"
    }
    reader = {
      username = "reader"
      secret   = "${var.name}-reader"
    }
    operator = {
      username = "clickhouse_operator"
      secret   = local.operator_fullname
    }
  }

  ################################################################################
  # S3
  ################################################################################

  s3_enabled = var.backup_enabled || var.cold_storage_enabled

  backup_path_prefix = coalesce(var.backup_path_prefix, "${var.namespace}/${var.name}")

  s3_bucket_name = !local.s3_enabled ? null : (
    var.s3_bucket_creation_enabled ? aws_s3_bucket.this[0].bucket : data.aws_s3_bucket.existing[0].bucket
  )
  s3_bucket_arn = !local.s3_enabled ? null : (
    var.s3_bucket_creation_enabled ? aws_s3_bucket.this[0].arn : data.aws_s3_bucket.existing[0].arn
  )
  s3_bucket_region = !local.s3_enabled ? null : (
    var.s3_bucket_creation_enabled ? local.region : data.aws_s3_bucket.existing[0].bucket_region
  )

  cluster_arn = data.aws_eks_cluster.this.arn
}
