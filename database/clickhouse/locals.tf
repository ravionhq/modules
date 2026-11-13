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
