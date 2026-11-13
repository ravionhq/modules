################################################################################
# Cluster connection
################################################################################

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster to install ClickHouse on."

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}

variable "region" {
  type        = string
  description = "AWS region of the cluster. Null uses the provider's default region."
  default     = null
}

variable "ravion_runner_role_arn" {
  type        = string
  description = "IAM role `aws eks get-token` assumes to reach the Kubernetes API. Null uses the caller's own credentials."
  default     = null
}

################################################################################
# Identity
################################################################################

variable "name" {
  type        = string
  description = "Name of the ClickHouse installation. Prefixes its Kubernetes objects, Services, secrets and AWS resources. Up to 24 lowercase letters, digits and hyphens."

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,22}[a-z0-9])?$", var.name))
    error_message = "name must be 1-24 lowercase letters, digits and hyphens, start with a letter and end with a letter or digit."
  }
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace for the operator, ClickHouse, Keeper and backups."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid Kubernetes namespace name."
  }
}

variable "namespace_creation_enabled" {
  type        = bool
  description = "Create the namespace. Turn off when it is managed elsewhere."
  default     = true
  nullable    = false
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to AWS resources."
  default     = {}
  nullable    = false
}

################################################################################
# Operator
################################################################################

variable "operator_chart_version" {
  type        = string
  description = "Version of the Altinity clickhouse-operator Helm chart. The operator image follows the chart's appVersion."
  default     = "0.27.4"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.operator_chart_version))
    error_message = "operator_chart_version must be a chart version such as 0.27.4."
  }
}

variable "operator_crds_management_enabled" {
  type        = bool
  description = "Install and upgrade the operator's cluster-scoped CRDs on every apply. With several installations on one cluster, keep this on for exactly one of them (the one with the newest operator) so an older operator never downgrades the shared CRDs."
  default     = true
  nullable    = false
}

variable "operator_resources" {
  type = object({
    cpu_request    = optional(string, "100m")
    memory_request = optional(string, "128Mi")
    memory_limit   = optional(string, "512Mi")
  })
  description = "Requests and limits for the operator container."
  default     = {}
  nullable    = false
}

################################################################################
# ClickHouse
################################################################################

variable "clickhouse_image" {
  type        = string
  description = "ClickHouse server image, including its tag. Pin an LTS release."
  default     = "clickhouse/clickhouse-server:26.8.36.3"
  nullable    = false

  validation {
    condition     = can(regex("^[^\\s:]+(:[0-9]+)?/?[^\\s:]*:[^\\s:]+$", var.clickhouse_image))
    error_message = "clickhouse_image must be an image reference with an explicit tag."
  }
}

variable "shard_count" {
  type        = number
  description = "Number of shards. One shard scales vertically a long way; adding shards later means redistributing existing data, so start with 1 unless one server cannot hold the data."
  default     = 1
  nullable    = false

  validation {
    condition     = var.shard_count >= 1 && var.shard_count <= 64 && floor(var.shard_count) == var.shard_count
    error_message = "shard_count must be a whole number from 1 to 64."
  }
}

variable "replica_count" {
  type        = number
  description = "Replicas per shard. 2 or more keeps the data available while a node or zone is down. Replicated tables need ClickHouse Keeper, which this module always runs."
  default     = 2
  nullable    = false

  validation {
    condition     = var.replica_count >= 1 && var.replica_count <= 10 && floor(var.replica_count) == var.replica_count
    error_message = "replica_count must be a whole number from 1 to 10."
  }
}

variable "clickhouse_resources" {
  type = object({
    cpu_request    = optional(string, "1")
    cpu_limit      = optional(string)
    memory_request = optional(string, "4Gi")
    memory_limit   = optional(string, "4Gi")
  })
  description = "Requests and limits for each ClickHouse server. ClickHouse caps its own memory at 90% of the container limit, so keep memory_limit set."
  default     = {}
  nullable    = false
}

variable "clickhouse_volume_size" {
  type        = string
  description = "Size of each ClickHouse server's data volume. Raising it later grows the volumes in place."
  default     = "50Gi"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi|Ti)$", var.clickhouse_volume_size))
    error_message = "clickhouse_volume_size must be a Kubernetes quantity in Mi, Gi or Ti, such as 50Gi."
  }
}

variable "storage_class_name" {
  type        = string
  description = "StorageClass for ClickHouse and Keeper volumes. It must allow volume expansion for size increases to apply."
  default     = "gp3"
  nullable    = false

  validation {
    condition     = length(var.storage_class_name) > 0
    error_message = "storage_class_name must not be empty."
  }
}

variable "volume_reclaim_policy" {
  type        = string
  description = "What happens to the data volumes when the installation is deleted: Retain keeps them, Delete removes them."
  default     = "Retain"
  nullable    = false

  validation {
    condition     = contains(["Retain", "Delete"], var.volume_reclaim_policy)
    error_message = "volume_reclaim_policy must be Retain or Delete."
  }
}

variable "clickhouse_settings" {
  type        = map(string)
  description = "Extra server settings, keyed by path as the operator expects (for example `max_concurrent_queries` or `logger/level`)."
  default     = {}
  nullable    = false
}

################################################################################
# Keeper
################################################################################

variable "keeper_image" {
  type        = string
  description = "ClickHouse Keeper image, including its tag. Keep it on the same release as clickhouse_image."
  default     = "clickhouse/clickhouse-keeper:26.8.36.3"
  nullable    = false

  validation {
    condition     = can(regex("^[^\\s:]+(:[0-9]+)?/?[^\\s:]*:[^\\s:]+$", var.keeper_image))
    error_message = "keeper_image must be an image reference with an explicit tag."
  }
}

variable "keeper_replica_count" {
  type        = number
  description = "Keeper nodes. 3 tolerates losing one; 1 has no redundancy and suits development only."
  default     = 3
  nullable    = false

  validation {
    condition     = contains([1, 3, 5], var.keeper_replica_count)
    error_message = "keeper_replica_count must be 1, 3 or 5."
  }
}

variable "keeper_resources" {
  type = object({
    cpu_request    = optional(string, "250m")
    cpu_limit      = optional(string)
    memory_request = optional(string, "512Mi")
    memory_limit   = optional(string, "1Gi")
  })
  description = "Requests and limits for each Keeper node."
  default     = {}
  nullable    = false
}

variable "keeper_volume_size" {
  type        = string
  description = "Size of each Keeper node's volume (logs and snapshots)."
  default     = "10Gi"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi|Ti)$", var.keeper_volume_size))
    error_message = "keeper_volume_size must be a Kubernetes quantity in Mi, Gi or Ti, such as 10Gi."
  }
}

################################################################################
# Placement
################################################################################

variable "zone_spread" {
  type        = string
  description = "How replicas of a shard, and Keeper nodes, spread across availability zones: preferred spreads when capacity allows, required refuses to schedule two replicas of a shard in one zone."
  default     = "preferred"
  nullable    = false

  validation {
    condition     = contains(["preferred", "required"], var.zone_spread)
    error_message = "zone_spread must be preferred or required."
  }
}

variable "priority_class" {
  type = object({
    enabled = optional(bool, false)
    value   = optional(number, 1000000)
  })
  description = "Create a PriorityClass for ClickHouse and Keeper so they are preempted and evicted after ordinary workloads."
  default     = {}
  nullable    = false

  validation {
    condition     = var.priority_class.value >= 0 && var.priority_class.value <= 1000000000
    error_message = "priority_class.value must be between 0 and 1000000000."
  }
}

variable "dedicated_node_pool" {
  type = object({
    enabled             = optional(bool, false)
    node_class_name     = optional(string, "default")
    capacity_types      = optional(list(string), ["on-demand"])
    instance_categories = optional(list(string), ["r", "m"])
    architectures       = optional(list(string), ["amd64"])
    cpu_limit           = optional(number, 64)
  })
  description = "Run ClickHouse and Keeper on a tainted Karpenter NodePool of their own. Needs Karpenter and an EC2NodeClass on the cluster."
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for type in var.dedicated_node_pool.capacity_types : contains(["on-demand", "spot"], type)])
    error_message = "dedicated_node_pool.capacity_types entries must be on-demand or spot."
  }

  validation {
    condition     = alltrue([for arch in var.dedicated_node_pool.architectures : contains(["amd64", "arm64"], arch)])
    error_message = "dedicated_node_pool.architectures entries must be amd64 or arm64."
  }

  validation {
    condition     = var.dedicated_node_pool.cpu_limit > 0
    error_message = "dedicated_node_pool.cpu_limit must be greater than 0."
  }
}

################################################################################
# Network
################################################################################

variable "network_policy_enabled" {
  type        = bool
  description = "Restrict ingress to ClickHouse and Keeper with NetworkPolicies. Needs a CNI that enforces them (for the VPC CNI, turn on its network policy agent)."
  default     = false
  nullable    = false
}

variable "network_policy_allowed_namespaces" {
  type        = list(string)
  description = "Namespaces whose pods may reach ClickHouse on its HTTP and native ports (and their TLS ports, with tls_enabled) when network policies are on. Pods in the installation's own namespace are always allowed."
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for namespace in var.network_policy_allowed_namespaces : can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", namespace))])
    error_message = "Each network_policy_allowed_namespaces entry must be a valid Kubernetes namespace name."
  }
}

################################################################################
# TLS
################################################################################

variable "tls_enabled" {
  type        = bool
  description = "Serve the native protocol over TLS on 9440 and HTTPS on 8443, with a server certificate from cert-manager, and send distributed queries between servers over TLS. Requires cert-manager, such as from the EKS Add-ons module. Clients then trust the ca.crt in the Secret named by the tls_ca_secret_name output."
  default     = false
  nullable    = false
}

variable "tls_disable_plaintext_ports" {
  type        = bool
  description = "With tls_enabled, close the plaintext native (9000) and HTTP (8123) ports, so every client must use TLS. The operator, probes, backups and the database job switch to the secure ports."
  default     = false
  nullable    = false
}

variable "tls_ca_source" {
  type        = string
  description = "Certificate authority that issues the server certificate. `self_signed` creates a CA in the namespace; `issuer` uses an existing cert-manager Issuer or ClusterIssuer, such as an AWS Private CA issuer; `secret` uses an existing CA key pair Secret in the namespace."
  default     = "self_signed"
  nullable    = false

  validation {
    condition     = contains(["self_signed", "issuer", "secret"], var.tls_ca_source)
    error_message = "The tls_ca_source must be self_signed, issuer or secret."
  }
}

variable "tls_issuer" {
  type = object({
    name  = string
    kind  = optional(string, "ClusterIssuer")
    group = optional(string, "cert-manager.io")
  })
  description = "Existing issuer for tls_ca_source = issuer. It must put the CA in the certificate Secret's ca.crt. For AWS Private CA through aws-privateca-issuer, use kind AWSPCAClusterIssuer or AWSPCAIssuer and group awspca.cert-manager.io."
  default     = null

  validation {
    condition     = var.tls_issuer == null || (can(regex("^[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])?$", var.tls_issuer.name)) && can(regex("^[A-Z][A-Za-z0-9]*$", var.tls_issuer.kind)) && can(regex("^[a-z0-9.-]+$", var.tls_issuer.group)))
    error_message = "tls_issuer needs a Kubernetes object name, a kind such as ClusterIssuer, and an API group such as cert-manager.io."
  }
}

variable "tls_ca_secret_name" {
  type        = string
  description = "For tls_ca_source = secret: a kubernetes.io/tls Secret in the namespace holding the CA certificate (tls.crt) and its private key (tls.key)."
  default     = null

  validation {
    condition     = var.tls_ca_secret_name == null || can(regex("^[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])?$", var.tls_ca_secret_name))
    error_message = "The tls_ca_secret_name must be a valid Kubernetes object name."
  }
}

variable "tls_extra_dns_names" {
  type        = list(string)
  description = "More names for the server certificate, such as a DNS name you point at a load balancer. The Service, every replica's pod and localhost are always included."
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for n in var.tls_extra_dns_names : can(regex("^[a-z0-9*]([a-z0-9.-]{0,251}[a-z0-9])?$", n))])
    error_message = "Each tls_extra_dns_names entry must be a DNS name."
  }
}

################################################################################
# Users and secrets
################################################################################

variable "database_name" {
  type        = string
  description = "Database to create on every server and to scope the writer and reader users to. Null creates none and grants on every database."
  default     = null

  validation {
    condition     = var.database_name == null || can(regex("^[A-Za-z_][A-Za-z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must start with a letter or underscore and contain only letters, digits and underscores."
  }

  validation {
    condition     = var.database_name == null || !contains(["system", "information_schema", "INFORMATION_SCHEMA", "default"], coalesce(var.database_name, "-"))
    error_message = "database_name must not be a built-in database."
  }
}

variable "database_engine" {
  type        = string
  description = "Engine for database_name. Replicated replicates table DDL to every replica on its own; Atomic needs ON CLUSTER in every DDL statement."
  default     = "Replicated"
  nullable    = false

  validation {
    condition     = contains(["Replicated", "Atomic"], var.database_engine)
    error_message = "database_engine must be Replicated or Atomic."
  }
}

variable "secrets_name_prefix" {
  type        = string
  description = "Prefix for the Secrets Manager secrets holding each user's credentials (<prefix>/admin, /writer, /reader, /operator). Null uses clickhouse/<cluster name>/<namespace>/<name>."
  default     = null

  validation {
    condition     = var.secrets_name_prefix == null || can(regex("^[A-Za-z0-9/_+=.@-]{1,480}$", coalesce(var.secrets_name_prefix, "-")))
    error_message = "secrets_name_prefix may contain letters, digits and /_+=.@- only."
  }
}

variable "secrets_kms_key_arn" {
  type        = string
  description = "KMS key to encrypt the credential secrets with. Null uses the AWS managed key. The External Secrets Operator's role needs kms:Decrypt on it."
  default     = null
}

variable "secrets_recovery_window_in_days" {
  type        = number
  description = "Days Secrets Manager keeps a deleted credential secret recoverable. 0 deletes it at once, which lets the same name be reused right away."
  default     = 7
  nullable    = false

  validation {
    condition     = var.secrets_recovery_window_in_days == 0 || (var.secrets_recovery_window_in_days >= 7 && var.secrets_recovery_window_in_days <= 30)
    error_message = "secrets_recovery_window_in_days must be 0 or from 7 to 30."
  }
}

variable "password_version" {
  type        = number
  description = "Bump to generate new passwords for every user. ClickHouse and the operator restart to pick them up, and clients must read the new secret values."
  default     = 1
  nullable    = false

  validation {
    condition     = var.password_version >= 1 && floor(var.password_version) == var.password_version
    error_message = "password_version must be a whole number of 1 or more."
  }
}

variable "external_secrets" {
  type = object({
    cluster_secret_store_name = optional(string)
    refresh_interval          = optional(string, "1h")
  })
  description = "How the External Secrets Operator reads the credentials. With no cluster_secret_store_name the module creates a namespaced SecretStore that uses the operator controller's own AWS credentials."
  default     = {}
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+(s|m|h)$", var.external_secrets.refresh_interval))
    error_message = "external_secrets.refresh_interval must be a duration such as 30m or 1h."
  }
}

variable "reader_limits" {
  type = object({
    max_execution_time_seconds = optional(number, 60)
    max_memory_usage_mib       = optional(number, 4096)
    max_concurrent_queries     = optional(number, 20)
  })
  description = "Ceilings for the reader user. The reader may lower them per query but never raise or remove them."
  default     = {}
  nullable    = false

  validation {
    condition     = var.reader_limits.max_execution_time_seconds >= 1 && var.reader_limits.max_memory_usage_mib >= 1 && var.reader_limits.max_concurrent_queries >= 1
    error_message = "reader_limits need max_execution_time_seconds >= 1, max_memory_usage_mib >= 1 and max_concurrent_queries >= 1."
  }
}

################################################################################
# S3
################################################################################

variable "s3_bucket_creation_enabled" {
  type        = bool
  description = "Create the S3 bucket for backups and the cold tier. Turn off to use an existing bucket named in s3_bucket_name."
  default     = true
  nullable    = false
}

variable "s3_bucket_name" {
  type        = string
  description = "Name for the new bucket (null generates one from name), or the existing bucket to use when creation is off."
  default     = null

  validation {
    condition     = var.s3_bucket_name == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", coalesce(var.s3_bucket_name, "-")))
    error_message = "s3_bucket_name must be a valid S3 bucket name."
  }
}

variable "s3_kms_key_arn" {
  type        = string
  description = "KMS key for the bucket's default encryption. Null uses SSE-S3. The ClickHouse role is granted use of the key."
  default     = null
}

variable "s3_noncurrent_version_expiration_days" {
  type        = number
  description = "Days the created bucket keeps overwritten or deleted object versions before expiring them."
  default     = 30
  nullable    = false

  validation {
    condition     = var.s3_noncurrent_version_expiration_days >= 1
    error_message = "s3_noncurrent_version_expiration_days must be at least 1."
  }
}

variable "s3_force_destroy" {
  type        = bool
  description = "Let destroying the module delete the created bucket with every backup and cold part in it."
  default     = false
  nullable    = false
}

################################################################################
# Backups
################################################################################

variable "backup_enabled" {
  type        = bool
  description = "Back up every shard to S3 on a schedule with clickhouse-backup."
  default     = true
  nullable    = false
}

variable "backup_schedule" {
  type        = string
  description = "Cron schedule for backups, in UTC."
  default     = "0 3 * * *"
  nullable    = false

  validation {
    condition     = length(split(" ", trimspace(var.backup_schedule))) == 5
    error_message = "backup_schedule must be a five-field cron expression."
  }
}

variable "backup_retention_count" {
  type        = number
  description = "Backups kept in S3 per shard. Older ones are deleted after each successful upload."
  default     = 7
  nullable    = false

  validation {
    condition     = var.backup_retention_count >= 1 && floor(var.backup_retention_count) == var.backup_retention_count
    error_message = "backup_retention_count must be a whole number of 1 or more."
  }
}

variable "backup_image" {
  type        = string
  description = "clickhouse-backup image, including its tag."
  default     = "altinity/clickhouse-backup:2.8.2"
  nullable    = false

  validation {
    condition     = can(regex("^[^\\s:]+(:[0-9]+)?/?[^\\s:]*:[^\\s:]+$", var.backup_image))
    error_message = "backup_image must be an image reference with an explicit tag."
  }
}

variable "backup_resources" {
  type = object({
    cpu_request    = optional(string, "100m")
    memory_request = optional(string, "256Mi")
    memory_limit   = optional(string, "1Gi")
  })
  description = "Requests and limits for the clickhouse-backup sidecar in each ClickHouse pod."
  default     = {}
  nullable    = false
}

variable "backup_job_image" {
  type        = string
  description = "Image the scheduled backup job runs to call each shard's clickhouse-backup API. Needs sh and curl."
  default     = "curlimages/curl:8.22.0"
  nullable    = false

  validation {
    condition     = can(regex("^[^\\s:]+(:[0-9]+)?/?[^\\s:]*:[^\\s:]+$", var.backup_job_image))
    error_message = "backup_job_image must be an image reference with an explicit tag."
  }
}

################################################################################
# Cold tier
################################################################################

variable "cold_storage_enabled" {
  type        = bool
  description = "Add an S3-backed `tiered` storage policy whose `cold` volume a table's TTL can move old parts to."
  default     = true
  nullable    = false
}

variable "cold_storage_cache_size" {
  type        = string
  description = "Local cache for reads from the cold tier, on each server's data volume."
  default     = "10Gi"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi|Ti)$", var.cold_storage_cache_size))
    error_message = "cold_storage_cache_size must be a Kubernetes quantity in Mi, Gi or Ti, such as 10Gi."
  }
}

################################################################################
# Metrics
################################################################################

variable "metrics_pod_monitors_enabled" {
  type        = bool
  description = "Create Prometheus Operator PodMonitors for ClickHouse, Keeper and the operator. Needs the monitoring.coreos.com CRDs."
  default     = false
  nullable    = false
}

variable "metrics_pod_monitor_labels" {
  type        = map(string)
  description = "Extra labels on the PodMonitors, for a Prometheus that selects monitors by label."
  default     = {}
  nullable    = false
}

variable "metrics_otlp_endpoint" {
  type        = string
  description = "OTLP/HTTP base URL to push ClickHouse, Keeper and operator metrics to, through a small OpenTelemetry collector the module runs. Null runs none."
  default     = null

  validation {
    condition     = var.metrics_otlp_endpoint == null || can(regex("^https?://\\S+$", coalesce(var.metrics_otlp_endpoint, "-")))
    error_message = "metrics_otlp_endpoint must be an http:// or https:// URL."
  }
}

variable "metrics_otlp_interval" {
  type        = string
  description = "How often the collector scrapes before pushing over OTLP."
  default     = "60s"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+(s|m)$", var.metrics_otlp_interval))
    error_message = "metrics_otlp_interval must be a duration such as 30s or 1m."
  }
}

variable "metrics_otlp_collector_image" {
  type        = string
  description = "OpenTelemetry Collector Contrib image for the OTLP metrics push."
  default     = "otel/opentelemetry-collector-contrib:0.161.0"
  nullable    = false

  validation {
    condition     = can(regex("^[^\\s:]+(:[0-9]+)?/?[^\\s:]*:[^\\s:]+$", var.metrics_otlp_collector_image))
    error_message = "metrics_otlp_collector_image must be an image reference with an explicit tag."
  }
}

################################################################################
# Helm
################################################################################

variable "helm_timeout_seconds" {
  type        = number
  description = "How long each Helm release may take, including the operator rolling out ClickHouse and the database creation job."
  default     = 1800
  nullable    = false

  validation {
    condition     = var.helm_timeout_seconds >= 300
    error_message = "helm_timeout_seconds must be at least 300."
  }
}
