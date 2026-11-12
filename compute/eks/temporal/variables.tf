################################################################################
# Cluster
################################################################################

variable "cluster_name" {
  type        = string
  description = "Name of the existing EKS cluster to install Temporal onto."

  validation {
    condition     = can(regex("^[0-9A-Za-z][A-Za-z0-9-_]{0,99}$", var.cluster_name))
    error_message = "The cluster_name must be 1-100 characters: start with alphanumeric, then alphanumerics, hyphens, or underscores (EKS cluster name constraints)."
  }
}

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
}

variable "ravion_runner_role_arn" {
  type        = string
  description = "IAM role assumed by `aws eks get-token` to authenticate to the Kubernetes API (ravion_runner_role_arn output of the compute/eks stack). When null, the identity running Terraform is used directly and must already have cluster access."
  default     = null

  validation {
    condition     = var.ravion_runner_role_arn == null || can(regex("^arn:aws", var.ravion_runner_role_arn))
    error_message = "The ravion_runner_role_arn must be an IAM role ARN starting with 'arn:aws'."
  }
}

################################################################################
# Release
################################################################################

variable "name" {
  type        = string
  description = "Helm release name. Every Kubernetes object the release creates is prefixed with it, such as <name>-frontend."
  default     = "temporal"

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,28}[a-z0-9])?$", var.name))
    error_message = "The name must be 1-30 lowercase letters, numbers and hyphens, start with a letter and end with a letter or number."
  }
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace for Temporal. A namespace of its own keeps the network policies and the CA secret away from other workloads."
  default     = "temporal"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.namespace))
    error_message = "The namespace must be 1-63 lowercase letters, numbers and hyphens, starting and ending with a letter or number."
  }
}

variable "namespace_creation_enabled" {
  type        = bool
  description = "Create the Kubernetes namespace. Turn off when it is managed elsewhere."
  default     = true
  nullable    = false
}

variable "chart_version" {
  type        = string
  description = "Version of the temporalio/helm-charts `temporal` chart. Chart 1.8.0 or newer is required for the TLS settings this module writes."
  default     = "1.8.0"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "The chart_version must be a semantic version such as 1.8.0."
  }
}

variable "server_image" {
  type        = string
  description = "Temporal server image, as repository:tag. The admin tools image (schema and namespace jobs) uses admin_tools_image."
  default     = "temporalio/server:1.32.2"
  nullable    = false

  validation {
    condition     = can(regex("^[^\\s]+:[^:/\\s]+$", var.server_image))
    error_message = "The server_image must be repository:tag."
  }
}

variable "admin_tools_image" {
  type        = string
  description = "Temporal admin tools image, as repository:tag. Keep it on the same Temporal version as server_image: it runs the schema migrations."
  default     = "temporalio/admin-tools:1.32.2"
  nullable    = false

  validation {
    condition     = can(regex("^[^\\s]+:[^:/\\s]+$", var.admin_tools_image))
    error_message = "The admin_tools_image must be repository:tag."
  }
}

variable "web_image" {
  type        = string
  description = "Temporal Web UI image, as repository:tag."
  default     = "temporalio/ui:2.56.1"
  nullable    = false

  validation {
    condition     = can(regex("^[^\\s]+:[^:/\\s]+$", var.web_image))
    error_message = "The web_image must be repository:tag."
  }
}

variable "log_level" {
  type        = string
  description = "Temporal server log level."
  default     = "info"
  nullable    = false

  validation {
    condition     = contains(["debug", "info", "warn", "error"], var.log_level)
    error_message = "The log_level must be one of debug, info, warn or error."
  }
}

variable "num_history_shards" {
  type        = number
  description = "Number of history shards. Fixed for the life of the cluster: it cannot be changed after the first install without a new database. Each shard costs a little memory and database load even when idle, and the shard count caps how far history can scale out. 512 suits most teams; choose 2048 or more for very high throughput."
  default     = 512
  nullable    = false

  validation {
    condition     = var.num_history_shards >= 1 && var.num_history_shards <= 65536 && floor(log(var.num_history_shards, 2)) == log(var.num_history_shards, 2)
    error_message = "The num_history_shards must be a power of two between 1 and 65536."
  }
}

################################################################################
# Database
################################################################################

variable "database_cluster_identifier" {
  type        = string
  description = "Identifier of the Aurora PostgreSQL cluster Temporal uses. The cluster must accept connections from the EKS cluster's pods."

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{0,62}$", var.database_cluster_identifier))
    error_message = "The database_cluster_identifier must be a valid Aurora cluster identifier."
  }
}

variable "database_username" {
  type        = string
  description = "Database user Temporal connects as. When null, the cluster's master username."
  default     = null
}

variable "database_password_source" {
  type        = string
  description = "Where the database password comes from. `external_secrets` copies it from Secrets Manager with the External Secrets Operator; `kubernetes_secret` reads an existing Kubernetes Secret in the namespace."
  default     = "external_secrets"
  nullable    = false

  validation {
    condition     = contains(["external_secrets", "kubernetes_secret"], var.database_password_source)
    error_message = "The database_password_source must be external_secrets or kubernetes_secret."
  }
}

variable "database_password_secret_arn" {
  type        = string
  description = "ARN of the Secrets Manager secret holding the database credentials as JSON, such as the Aurora cluster's master user secret. Required when database_password_source is external_secrets."
  default     = null

  validation {
    condition     = var.database_password_secret_arn == null || can(regex("^arn:aws[a-z-]*:secretsmanager:", var.database_password_secret_arn))
    error_message = "The database_password_secret_arn must be a Secrets Manager secret ARN."
  }
}

variable "database_password_secret_property" {
  type        = string
  description = "JSON key in the Secrets Manager secret that holds the password."
  default     = "password"
  nullable    = false
}

variable "database_password_secret_store_name" {
  type        = string
  description = "External Secrets ClusterSecretStore that reads Secrets Manager. It must admit this namespace and be allowed to read the secret (and decrypt it, for a customer managed KMS key)."
  default     = "ravion-aws"
  nullable    = false
}

variable "database_password_refresh_interval" {
  type        = string
  description = "How often the External Secrets Operator re-reads the password."
  default     = "1h"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+(s|m|h)$", var.database_password_refresh_interval))
    error_message = "The database_password_refresh_interval must be a duration such as 30m or 1h."
  }
}

variable "database_password_kubernetes_secret_name" {
  type        = string
  description = "Kubernetes Secret holding the password under the key `password`. With external_secrets it is created under this name; when null, <name>-db."
  default     = null

  validation {
    condition     = var.database_password_kubernetes_secret_name == null || can(regex("^[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])?$", var.database_password_kubernetes_secret_name))
    error_message = "The database_password_kubernetes_secret_name must be a valid Kubernetes object name."
  }
}

variable "database_name" {
  type        = string
  description = "Database holding Temporal's persistence (workflow state and history)."
  default     = "temporal"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_]{0,62}$", var.database_name))
    error_message = "The database_name must be 1-63 lowercase letters, numbers and underscores, not starting with a number."
  }
}

variable "visibility_database_name" {
  type        = string
  description = "Database holding Temporal's visibility records (workflow search and listing)."
  default     = "temporal_visibility"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_]{0,62}$", var.visibility_database_name))
    error_message = "The visibility_database_name must be 1-63 lowercase letters, numbers and underscores, not starting with a number."
  }
}

variable "database_schema_management_enabled" {
  type        = bool
  description = "Create both databases if missing and run Temporal's schema migrations on every deploy. Turn off only when a database administrator manages the schema."
  default     = true
  nullable    = false
}

variable "database_tls_enabled" {
  type        = bool
  description = "Connect to the database over TLS and verify its certificate against the RDS CA bundle."
  default     = true
  nullable    = false
}

variable "database_max_connections" {
  type        = number
  description = "Maximum connections each Temporal server pod opens to the persistence database. Multiply by the number of server pods to size the database's max_connections."
  default     = 20
  nullable    = false

  validation {
    condition     = var.database_max_connections >= 1 && var.database_max_connections <= 1000
    error_message = "The database_max_connections must be between 1 and 1000."
  }
}

variable "visibility_database_max_connections" {
  type        = number
  description = "Maximum connections each Temporal server pod opens to the visibility database."
  default     = 10
  nullable    = false

  validation {
    condition     = var.visibility_database_max_connections >= 1 && var.visibility_database_max_connections <= 1000
    error_message = "The visibility_database_max_connections must be between 1 and 1000."
  }
}

################################################################################
# Services
################################################################################

variable "frontend" {
  type = object({
    replicas       = optional(number, 2)
    cpu_request    = optional(string, "250m")
    memory_request = optional(string, "256Mi")
    memory_limit   = optional(string, "512Mi")
  })
  description = "Frontend service: the gRPC API SDK clients, the Web UI and the CLI call."
  default     = {}
  nullable    = false

  validation {
    condition     = var.frontend.replicas >= 1 && can(regex("^[0-9]+(Mi|Gi)$", var.frontend.memory_request)) && can(regex("^[0-9]+(Mi|Gi)$", var.frontend.memory_limit)) && can(regex("^[0-9]+(\\.[0-9]+)?m?$", var.frontend.cpu_request))
    error_message = "frontend: replicas must be at least 1, CPU a Kubernetes quantity such as 250m, and memory in Mi or Gi such as 512Mi."
  }
}

variable "history" {
  type = object({
    replicas       = optional(number, 2)
    cpu_request    = optional(string, "500m")
    memory_request = optional(string, "1Gi")
    memory_limit   = optional(string, "2Gi")
  })
  description = "History service: owns the history shards and does most of the work. Scale it first, and give it memory: each pod caches the workflows of the shards it owns."
  default     = {}
  nullable    = false

  validation {
    condition     = var.history.replicas >= 1 && can(regex("^[0-9]+(Mi|Gi)$", var.history.memory_request)) && can(regex("^[0-9]+(Mi|Gi)$", var.history.memory_limit)) && can(regex("^[0-9]+(\\.[0-9]+)?m?$", var.history.cpu_request))
    error_message = "history: replicas must be at least 1, CPU a Kubernetes quantity such as 500m, and memory in Mi or Gi such as 2Gi."
  }
}

variable "matching" {
  type = object({
    replicas       = optional(number, 2)
    cpu_request    = optional(string, "250m")
    memory_request = optional(string, "256Mi")
    memory_limit   = optional(string, "512Mi")
  })
  description = "Matching service: hosts the task queues workers poll."
  default     = {}
  nullable    = false

  validation {
    condition     = var.matching.replicas >= 1 && can(regex("^[0-9]+(Mi|Gi)$", var.matching.memory_request)) && can(regex("^[0-9]+(Mi|Gi)$", var.matching.memory_limit)) && can(regex("^[0-9]+(\\.[0-9]+)?m?$", var.matching.cpu_request))
    error_message = "matching: replicas must be at least 1, CPU a Kubernetes quantity such as 250m, and memory in Mi or Gi such as 512Mi."
  }
}

variable "worker" {
  type = object({
    replicas       = optional(number, 1)
    cpu_request    = optional(string, "100m")
    memory_request = optional(string, "256Mi")
    memory_limit   = optional(string, "512Mi")
  })
  description = "Internal worker service: runs Temporal's own system workflows, such as scheduled actions and batch operations."
  default     = {}
  nullable    = false

  validation {
    condition     = var.worker.replicas >= 1 && can(regex("^[0-9]+(Mi|Gi)$", var.worker.memory_request)) && can(regex("^[0-9]+(Mi|Gi)$", var.worker.memory_limit)) && can(regex("^[0-9]+(\\.[0-9]+)?m?$", var.worker.cpu_request))
    error_message = "worker: replicas must be at least 1, CPU a Kubernetes quantity such as 100m, and memory in Mi or Gi such as 512Mi."
  }
}

################################################################################
# Temporal namespaces
################################################################################

variable "temporal_namespaces" {
  type        = map(number)
  description = "Temporal namespaces created on install, keyed by name, each with how many days closed workflows are kept. Namespaces that already exist are left as they are: change retention with `temporal operator namespace update`."
  default     = { default = 7 }
  nullable    = false

  validation {
    condition     = alltrue([for name, days in var.temporal_namespaces : can(regex("^[A-Za-z0-9][A-Za-z0-9._-]{1,254}$", name)) && days >= 1 && days <= 3650 && floor(days) == days])
    error_message = "Each Temporal namespace needs a 2-255 character name of letters, numbers, dots, underscores and hyphens, and whole-day retention between 1 and 3650."
  }
}

################################################################################
# Placement and resilience
################################################################################

variable "topology_spread" {
  type        = string
  description = "Spread each service's replicas across zones and nodes. `preferred` spreads when it can; `required` refuses to schedule a replica that would break the spread, which needs nodes in every zone (Karpenter adds them); `off` leaves placement to the scheduler."
  default     = "preferred"
  nullable    = false

  validation {
    condition     = contains(["preferred", "required", "off"], var.topology_spread)
    error_message = "The topology_spread must be preferred, required or off."
  }
}

variable "pod_disruption_budgets_enabled" {
  type        = bool
  description = "Let voluntary disruptions, such as node drains, take at most one replica of each service at a time."
  default     = true
  nullable    = false
}

variable "priority_class_creation_enabled" {
  type        = bool
  description = "Create a PriorityClass ranking Temporal above ordinary workloads, so the scheduler preempts and the kubelet evicts other pods first."
  default     = false
  nullable    = false
}

variable "priority_class_name" {
  type        = string
  description = "PriorityClass for every Temporal pod. With priority_class_creation_enabled it is created under this name (when null, <name>-critical); otherwise it must already exist, or be null for none."
  default     = null
}

variable "priority_class_value" {
  type        = number
  description = "Priority of the created PriorityClass. Keep it below the system-cluster-critical (2000000000) and system-node-critical classes."
  default     = 1000000
  nullable    = false

  validation {
    condition     = var.priority_class_value >= 0 && var.priority_class_value <= 1000000000
    error_message = "The priority_class_value must be between 0 and 1000000000."
  }
}

variable "node_pool_creation_enabled" {
  type        = bool
  description = "Create a dedicated, tainted Karpenter NodePool and run Temporal on it alone, so other workloads cannot starve it and node consolidation moves its pods one node at a time. Requires Karpenter, such as from the EKS Add-ons module."
  default     = false
  nullable    = false
}

variable "node_pool" {
  type = object({
    ec2_node_class_name = optional(string, "default")
    capacity_types      = optional(list(string), ["on-demand"])
    instance_categories = optional(list(string), ["c", "m", "r"])
    architectures       = optional(list(string), ["amd64"])
    cpu_limit           = optional(number, 32)
    consolidate_after   = optional(string, "1h")
  })
  description = "Settings for the dedicated NodePool. Spot capacity is allowed but not recommended: a reclaim moves history shards mid-flight."
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for c in var.node_pool.capacity_types : contains(["on-demand", "spot"], c)]) && length(var.node_pool.capacity_types) > 0
    error_message = "node_pool.capacity_types must list on-demand, spot or both."
  }

  validation {
    condition     = alltrue([for a in var.node_pool.architectures : contains(["amd64", "arm64"], a)]) && length(var.node_pool.architectures) > 0
    error_message = "node_pool.architectures must list amd64, arm64 or both."
  }

  validation {
    condition     = var.node_pool.cpu_limit >= 1 && can(regex("^[0-9]+(s|m|h)$", var.node_pool.consolidate_after))
    error_message = "node_pool.cpu_limit must be at least 1 and node_pool.consolidate_after a duration such as 1h."
  }
}

################################################################################
# Network policy
################################################################################

variable "network_policy_enabled" {
  type        = bool
  description = "Close the Temporal pods' internal ports to everything outside the release. Enforcement needs a CNI that implements NetworkPolicy, such as the Amazon VPC CNI with network policy turned on; without one the policies are inert."
  default     = true
  nullable    = false
}

variable "network_policy_frontend_client_namespaces" {
  type        = list(string)
  description = "Namespaces whose pods may call the frontend (gRPC 7233, HTTP 7243). Empty allows every namespace in the cluster."
  default     = []
  nullable    = false
}

variable "network_policy_web_client_namespaces" {
  type        = list(string)
  description = "Namespaces whose pods may reach the Web UI, such as an ingress controller's. Empty allows every namespace in the cluster."
  default     = []
  nullable    = false
}

variable "network_policy_web_client_cidrs" {
  type        = list(string)
  description = "CIDR blocks that may reach the Web UI pods directly. The VPC CIDR is added automatically when the Web UI ingress is enabled."
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for c in var.network_policy_web_client_cidrs : can(cidrhost(c, 0))])
    error_message = "Each network_policy_web_client_cidrs entry must be a CIDR block."
  }
}

variable "network_policy_metrics_namespaces" {
  type        = list(string)
  description = "Namespaces whose pods may scrape the servers' metrics port (9090). Empty allows every namespace in the cluster."
  default     = []
  nullable    = false
}

################################################################################
# TLS
################################################################################

variable "tls_enabled" {
  type        = bool
  description = "Encrypt Temporal's traffic with certificates from a private CA that cert-manager creates in the namespace: mutual TLS between Temporal's services, and TLS on the frontend. Requires cert-manager, such as from the EKS Add-ons module. SDK clients must then connect with TLS and trust the CA in the frontend certificate secret's ca.crt."
  default     = false
  nullable    = false
}

variable "tls_frontend_client_auth_required" {
  type        = bool
  description = "Require SDK clients to present a certificate from the private CA (mutual TLS) on the frontend."
  default     = false
  nullable    = false
}

################################################################################
# Web UI
################################################################################

variable "web_enabled" {
  type        = bool
  description = "Run the Temporal Web UI. It has no sign-in of its own: anyone who can reach it can read and act on every namespace."
  default     = true
  nullable    = false
}

variable "web" {
  type = object({
    replicas       = optional(number, 1)
    cpu_request    = optional(string, "50m")
    memory_request = optional(string, "128Mi")
    memory_limit   = optional(string, "256Mi")
  })
  description = "Web UI replicas and resources."
  default     = {}
  nullable    = false

  validation {
    condition     = var.web.replicas >= 1 && can(regex("^[0-9]+(Mi|Gi)$", var.web.memory_request)) && can(regex("^[0-9]+(Mi|Gi)$", var.web.memory_limit)) && can(regex("^[0-9]+(\\.[0-9]+)?m?$", var.web.cpu_request))
    error_message = "web: replicas must be at least 1, CPU a Kubernetes quantity such as 50m, and memory in Mi or Gi such as 256Mi."
  }
}

variable "web_ingress_enabled" {
  type        = bool
  description = "Expose the Web UI through an Ingress. With the default `alb` class it is an internal Application Load Balancer, reachable only from inside the VPC and networks connected to it."
  default     = false
  nullable    = false
}

variable "web_ingress_class_name" {
  type        = string
  description = "IngressClass for the Web UI. `alb` is the AWS Load Balancer Controller's."
  default     = "alb"
  nullable    = false
}

variable "web_ingress_host" {
  type        = string
  description = "Host name the Web UI Ingress answers on. When null, every host."
  default     = null
}

variable "web_ingress_certificate_arn" {
  type        = string
  description = "ACM certificate for HTTPS on the internal ALB (alb class only). When null, the ALB listens on HTTP 80."
  default     = null

  validation {
    condition     = var.web_ingress_certificate_arn == null || can(regex("^arn:aws[a-z-]*:acm:", var.web_ingress_certificate_arn))
    error_message = "The web_ingress_certificate_arn must be an ACM certificate ARN."
  }
}

variable "web_ingress_annotations" {
  type        = map(string)
  description = "Annotations merged over the module's Ingress annotations, for example to join a shared ALB with alb.ingress.kubernetes.io/group.name."
  default     = {}
  nullable    = false
}

################################################################################
# Metrics
################################################################################

variable "metrics_prometheus_annotations_enabled" {
  type        = bool
  description = "Annotate the server pods with prometheus.io/scrape, for scrapers that discover pods by annotation."
  default     = true
  nullable    = false
}

variable "metrics_service_monitor_enabled" {
  type        = bool
  description = "Create Prometheus Operator ServiceMonitors for the servers. Requires the monitoring.coreos.com CRDs."
  default     = false
  nullable    = false
}

variable "metrics_otlp_endpoint" {
  type        = string
  description = "OTLP gRPC endpoint (host:port or http://host:port) to push the servers' metrics to, such as the EKS Add-ons module's otlp_grpc_endpoint output. A small forwarder in the namespace scrapes the servers and pushes the samples. When null, no forwarder runs."
  default     = null
}

variable "metrics_otlp_metric_families" {
  type        = list(string)
  description = "Metric families the forwarder keeps, as regular expressions without the _bucket/_sum/_count/_total suffixes. Empty keeps everything, which can be many series on a busy cluster."
  default = [
    "service_requests", "service_errors.*", "service_latency", "service_pending_requests",
    "persistence_requests", "persistence_errors.*", "persistence_latency",
    "task_requests", "task_errors.*", "task_latency_queue", "task_latency_processing", "task_schedule_to_start_latency",
    "lock_requests", "lock_latency", "acquire_shards_count", "acquire_shards_latency", "sharditem_.*", "membership_changed_count",
    "approximate_backlog_count", "approximate_backlog_age_seconds", "poll_success", "poll_success_sync", "poll_timeouts", "no_poller_tasks",
    "workflow_success", "workflow_failed", "workflow_timeout", "workflow_terminate", "workflow_cancel", "workflow_continued_as_new",
    "state_transition_count", "schedule_.*", "num_goroutines", "memory_heap", "memory_allocated", "memory_gc_pause_ms", "restarts",
  ]
  nullable = false
}

variable "metrics_otlp_collector_image" {
  type        = string
  description = "OpenTelemetry Collector image for the metrics forwarder. It must include the prometheus receiver and the otlp_grpc exporter."
  default     = "otel/opentelemetry-collector-contrib:0.161.0"
  nullable    = false
}

################################################################################
# Escape hatch
################################################################################

variable "helm_values" {
  type        = list(string)
  description = "Extra YAML values documents for the upstream Temporal chart, applied after the module's own values, for settings this module has no input for (Web UI sign-in, authorization, dynamic config)."
  default     = []
  nullable    = false
}

variable "helm_timeout_seconds" {
  type        = number
  description = "How long an install or upgrade waits for the schema job and every Temporal pod to be ready."
  default     = 900
  nullable    = false

  validation {
    condition     = var.helm_timeout_seconds >= 60 && var.helm_timeout_seconds <= 3600
    error_message = "The helm_timeout_seconds must be between 60 and 3600."
  }
}

variable "tags" {
  type        = map(string)
  description = "A map of tags applied, as provider default tags, to any AWS resource the module creates."
  default     = {}
  nullable    = false
}
