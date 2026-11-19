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

variable "external_secrets_store_name" {
  type        = string
  description = "External Secrets ClusterSecretStore that reads Secrets Manager, for the database password, the JWKS key set, the Web UI's OIDC client and the frontend's secret environment and files. It must admit this namespace and be allowed to read each secret (and decrypt it, for a customer managed KMS key)."
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
  type = map(object({
    retention_days    = optional(number, 7)
    search_attributes = optional(map(string), {})
  }))
  description = "Temporal namespaces, keyed by name. After every deploy a job creates each missing namespace, sets its retention (days closed workflows are kept), and registers its custom search attributes (name => type: Keyword, KeywordList, Text, Int, Double, Bool or Datetime). Attributes are only ever added: removing one here leaves it registered. Postgres visibility gives each namespace 10 Keyword slots and 3 of every other type."
  default     = { default = {} }
  nullable    = false

  validation {
    condition     = alltrue([for name, ns in var.temporal_namespaces : can(regex("^[A-Za-z0-9][A-Za-z0-9._-]{1,254}$", name)) && ns.retention_days >= 1 && ns.retention_days <= 3650 && floor(ns.retention_days) == ns.retention_days])
    error_message = "Each Temporal namespace needs a 2-255 character name of letters, numbers, dots, underscores and hyphens, and whole-day retention between 1 and 3650."
  }

  validation {
    condition = alltrue(flatten([for ns in var.temporal_namespaces : [
      for attr, type in ns.search_attributes :
      can(regex("^[A-Za-z][A-Za-z0-9_]{0,63}$", attr)) && contains(["Keyword", "KeywordList", "Text", "Int", "Double", "Bool", "Datetime"], type)
    ]]))
    error_message = "Search attribute names must be 1-64 letters, numbers and underscores starting with a letter, and each type one of Keyword, KeywordList, Text, Int, Double, Bool or Datetime."
  }

  validation {
    condition = alltrue(flatten([for ns in var.temporal_namespaces : [
      for type, limit in { Keyword = 10, KeywordList = 3, Text = 3, Int = 3, Double = 3, Bool = 3, Datetime = 3 } :
      length([for t in values(ns.search_attributes) : t if t == type]) <= limit
    ]]))
    error_message = "Postgres visibility allows each namespace at most 10 Keyword search attributes and 3 of each other type."
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

variable "tls_frontend_extra_dns_names" {
  type        = list(string)
  description = "More names for the frontend certificate, such as a DNS name you point at the NLB. The tailnet name is added automatically when tailscale_tailnet_domain is set."
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for n in var.tls_frontend_extra_dns_names : can(regex("^[a-z0-9*]([a-z0-9.-]{0,251}[a-z0-9])?$", n))])
    error_message = "Each tls_frontend_extra_dns_names entry must be a DNS name."
  }
}

variable "tls_ca_source" {
  type        = string
  description = "Certificate authority that issues the frontend and internode certificates. `self_signed` creates a CA in the namespace; `issuer` uses an existing cert-manager Issuer or ClusterIssuer, such as an AWS Private CA issuer; `secret` uses an existing CA key pair Secret in the namespace."
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
  description = "Existing issuer for tls_ca_source = issuer. For AWS Private CA through aws-privateca-issuer, use kind AWSPCAClusterIssuer or AWSPCAIssuer and group awspca.cert-manager.io."
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

################################################################################
# JWT authorization
################################################################################

variable "jwt_auth_enabled" {
  type        = bool
  description = "Require a JWT on every frontend call, checked by Temporal's default claim mapper and authorizer. The token's permissions claim lists entries of the form <namespace>:<read|write|worker|admin> (system:admin for cluster-wide admin). Requires tls_enabled: Temporal's own components then reach the cluster through an internal frontend with their internode certificates, as admin."
  default     = false
  nullable    = false
}

variable "jwt_auth_audience" {
  type        = string
  description = "Audience (aud) the frontend requires in tokens. When null, the audience is not checked."
  default     = null
}

variable "jwt_auth_permissions_claim_name" {
  type        = string
  description = "Token claim holding the permissions list."
  default     = "permissions"
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9_:/.-]{1,128}$", var.jwt_auth_permissions_claim_name))
    error_message = "The jwt_auth_permissions_claim_name must be 1-128 characters of letters, numbers and _ : / . -"
  }
}

variable "jwt_auth_jwks_source" {
  type        = string
  description = "Where the frontend reads the signing keys. `url` fetches one or more JWKS URLs, such as an identity provider's; `secrets_manager` syncs a JWKS document from Secrets Manager through External Secrets and serves it inside the namespace, for tokens you sign yourself."
  default     = "url"
  nullable    = false

  validation {
    condition     = contains(["url", "secrets_manager"], var.jwt_auth_jwks_source)
    error_message = "The jwt_auth_jwks_source must be url or secrets_manager."
  }
}

variable "jwt_auth_jwks_urls" {
  type        = list(string)
  description = "JWKS URLs for jwt_auth_jwks_source = url. The frontend drops a whole refresh when any of them fails, so list only reliable ones."
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for u in var.jwt_auth_jwks_urls : can(regex("^https?://\\S+$", u))])
    error_message = "Each jwt_auth_jwks_urls entry must be an http(s) URL."
  }
}

variable "jwt_auth_jwks_secret_arn" {
  type        = string
  description = "Secrets Manager secret holding the JWKS document ({\"keys\": [...]}) for jwt_auth_jwks_source = secrets_manager."
  default     = null

  validation {
    condition     = var.jwt_auth_jwks_secret_arn == null || can(regex("^arn:aws[a-z-]*:secretsmanager:", var.jwt_auth_jwks_secret_arn))
    error_message = "The jwt_auth_jwks_secret_arn must be a Secrets Manager secret ARN."
  }
}

variable "jwt_auth_jwks_secret_property" {
  type        = string
  description = "JSON key holding the JWKS document inside the secret. When null, the whole secret string is the document."
  default     = null
}

variable "jwt_auth_jwks_refresh_interval" {
  type        = string
  description = "How often the frontend reloads the signing keys, and how often External Secrets re-reads them from Secrets Manager."
  default     = "1m"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+(s|m|h)$", var.jwt_auth_jwks_refresh_interval))
    error_message = "The jwt_auth_jwks_refresh_interval must be a duration such as 1m."
  }
}

variable "jwt_auth_jwks_server_image" {
  type        = string
  description = "Image of the small web server that serves a JWKS document synced from Secrets Manager. It must serve /usr/share/nginx/html on port 8080 as a non-root user."
  default     = "nginxinc/nginx-unprivileged:1.28.1-alpine"
  nullable    = false
}

variable "internal_frontend" {
  type = object({
    replicas       = optional(number, 2)
    cpu_request    = optional(string, "100m")
    memory_request = optional(string, "256Mi")
    memory_limit   = optional(string, "512Mi")
  })
  description = "Internal frontend, run when jwt_auth_enabled: Temporal's own workers, the admin tools and the setup jobs call it with internode certificates instead of tokens."
  default     = {}
  nullable    = false

  validation {
    condition     = var.internal_frontend.replicas >= 1 && can(regex("^[0-9]+(Mi|Gi)$", var.internal_frontend.memory_request)) && can(regex("^[0-9]+(Mi|Gi)$", var.internal_frontend.memory_limit)) && can(regex("^[0-9]+(\\.[0-9]+)?m?$", var.internal_frontend.cpu_request))
    error_message = "internal_frontend: replicas must be at least 1, CPU a Kubernetes quantity such as 100m, and memory in Mi or Gi such as 512Mi."
  }
}

variable "web_internal_frontend_enabled" {
  type        = bool
  description = "Connect the Web UI through the internal frontend with an internode certificate, so it acts as admin without a token. With jwt_auth_enabled the UI otherwise needs each user's token, from OIDC sign-in. Only for a Web UI that already restricts who reaches it."
  default     = false
  nullable    = false
}

################################################################################
# Frontend customization (custom claim mappers and other server builds)
################################################################################

variable "frontend_extra_env" {
  type        = map(string)
  description = "Plain environment variables for the frontend pods, such as settings for a custom claim mapper in your own server_image."
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for k in keys(var.frontend_extra_env) : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", k)) && k != "GOMEMLIMIT"])
    error_message = "frontend_extra_env names must be valid environment variable names, and GOMEMLIMIT is set by the module."
  }
}

variable "frontend_secret_env" {
  type = map(object({
    secret_arn = string
    property   = optional(string)
  }))
  description = "Environment variables for the frontend pods read from Secrets Manager, keyed by variable name. External Secrets syncs them into a Kubernetes Secret, so the values stay out of Helm values and Terraform state. Without property, the whole secret string is the value."
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for k, v in var.frontend_secret_env : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", k)) && can(regex("^arn:aws[a-z-]*:secretsmanager:", v.secret_arn))])
    error_message = "frontend_secret_env names must be valid environment variable names, each with a Secrets Manager secret ARN."
  }

  validation {
    condition     = length(setintersection(keys(var.frontend_secret_env), keys(var.frontend_extra_env))) == 0
    error_message = "A variable cannot be in both frontend_extra_env and frontend_secret_env."
  }
}

variable "server_secret_files" {
  type = map(object({
    secret_arn = string
    property   = optional(string)
  }))
  description = "Secrets Manager secrets mounted as read-only files into the Temporal server pods, keyed by absolute file path, such as a service account key a custom claim mapper reads. Without property, the whole secret string is the file. Files are not refreshed in running pods: restart them after a change."
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for path, f in var.server_secret_files : can(regex("^arn:aws[a-z-]*:secretsmanager:", f.secret_arn)) && can(regex("^/[A-Za-z0-9._/-]*[A-Za-z0-9._-]$", path)) && !startswith(path, "/etc/temporal/")])
    error_message = "Each server_secret_files entry needs an absolute file path outside /etc/temporal/ and a Secrets Manager secret ARN."
  }
}

################################################################################
# Internal NLB for the frontend
################################################################################

variable "frontend_nlb_enabled" {
  type        = bool
  description = "Expose the frontend's gRPC port on an internal Network Load Balancer, for clients outside the cluster, such as in a peered VPC. TCP passes straight through, so TLS and token checks still happen at the frontend. Requires the AWS Load Balancer Controller."
  default     = false
  nullable    = false
}

variable "frontend_nlb_name" {
  type        = string
  description = "Name of the NLB, unique in the account and region. When null, <cluster name>-<name>, cut to 32 characters."
  default     = null

  validation {
    condition     = var.frontend_nlb_name == null || can(regex("^[A-Za-z0-9]([A-Za-z0-9-]{0,30}[A-Za-z0-9])?$", var.frontend_nlb_name))
    error_message = "The frontend_nlb_name must be 1-32 letters, numbers and hyphens, not starting or ending with a hyphen."
  }
}

variable "frontend_nlb_subnet_ids" {
  type        = list(string)
  description = "Private subnets for the NLB. When empty, the load balancer controller picks the subnets tagged kubernetes.io/role/internal-elb."
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for s in var.frontend_nlb_subnet_ids : can(regex("^subnet-[0-9a-f]+$", s))])
    error_message = "Each frontend_nlb_subnet_ids entry must be a subnet ID."
  }
}

variable "frontend_nlb_source_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to reach the NLB. They are also admitted to the frontend by the network policy, since the NLB keeps client addresses."
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for c in var.frontend_nlb_source_cidrs : can(cidrhost(c, 0))])
    error_message = "Each frontend_nlb_source_cidrs entry must be a CIDR block."
  }
}

variable "frontend_nlb_cross_zone_enabled" {
  type        = bool
  description = "Spread NLB traffic across frontend pods in every zone, not only the client's zone. Cross-zone traffic is charged."
  default     = true
  nullable    = false
}

variable "frontend_nlb_deletion_protection_enabled" {
  type        = bool
  description = "Protect the NLB from deletion. Turn it off before removing the NLB."
  default     = false
  nullable    = false
}

################################################################################
# Tailscale
################################################################################

variable "tailscale_frontend_enabled" {
  type        = bool
  description = "Put the frontend's gRPC port on your tailnet through the Tailscale Kubernetes operator. TCP passes straight through, so TLS and token checks still happen at the frontend."
  default     = false
  nullable    = false
}

variable "tailscale_frontend_hostname" {
  type        = string
  description = "Tailnet device name for the frontend. When null, <name>-frontend."
  default     = null

  validation {
    condition     = var.tailscale_frontend_hostname == null || can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.tailscale_frontend_hostname))
    error_message = "The tailscale_frontend_hostname must be a DNS label of lowercase letters, numbers and hyphens."
  }
}

variable "tailscale_frontend_tags" {
  type        = list(string)
  description = "Tailscale tags for the frontend's device, such as tag:workflows-grpc. When empty, the operator's default tags. Grant access to the tag in your tailnet policy."
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for t in var.tailscale_frontend_tags : can(regex("^tag:[A-Za-z0-9-]+$", t))])
    error_message = "Each Tailscale tag must look like tag:name."
  }
}

variable "tailscale_web_enabled" {
  type        = bool
  description = "Serve the Web UI on your tailnet over HTTPS through the Tailscale Kubernetes operator's Ingress."
  default     = false
  nullable    = false
}

variable "tailscale_web_hostname" {
  type        = string
  description = "Tailnet device name for the Web UI. When null, the release name."
  default     = null

  validation {
    condition     = var.tailscale_web_hostname == null || can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.tailscale_web_hostname))
    error_message = "The tailscale_web_hostname must be a DNS label of lowercase letters, numbers and hyphens."
  }
}

variable "tailscale_web_tags" {
  type        = list(string)
  description = "Tailscale tags for the Web UI's device. When empty, the operator's default tags. Grant access to the tag in your tailnet policy."
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for t in var.tailscale_web_tags : can(regex("^tag:[A-Za-z0-9-]+$", t))])
    error_message = "Each Tailscale tag must look like tag:name."
  }
}

variable "tailscale_namespace" {
  type        = string
  description = "Namespace the Tailscale operator runs its proxies in. The network policies admit it to the frontend and the Web UI."
  default     = "tailscale"
  nullable    = false
}

variable "tailscale_tailnet_domain" {
  type        = string
  description = "Your tailnet's MagicDNS domain, such as example-tailnet.ts.net. Used to derive the tailnet addresses in the outputs and the Web UI's OIDC callback URL."
  default     = null

  validation {
    condition     = var.tailscale_tailnet_domain == null || can(regex("^[a-z0-9-]+(\\.[a-z0-9-]+)+$", var.tailscale_tailnet_domain))
    error_message = "The tailscale_tailnet_domain must be a domain such as example-tailnet.ts.net."
  }
}

################################################################################
# Web UI sign-in (OIDC)
################################################################################

variable "web_oidc_enabled" {
  type        = bool
  description = "Require sign-in to the Web UI through an OpenID Connect provider."
  default     = false
  nullable    = false
}

variable "web_oidc_provider" {
  type        = string
  description = "Identity provider preset. `google` fills the issuer URL and scopes; `okta` and `microsoft_entra` fill the scopes and need your organization's issuer URL; `generic` needs both."
  default     = "google"
  nullable    = false

  validation {
    condition     = contains(["google", "okta", "microsoft_entra", "generic"], var.web_oidc_provider)
    error_message = "The web_oidc_provider must be google, okta, microsoft_entra or generic."
  }
}

variable "web_oidc_issuer_url" {
  type        = string
  description = "OIDC issuer URL, overriding the preset: https://<org>.okta.com (or an authorization server) for Okta, https://login.microsoftonline.com/<tenant ID>/v2.0 for Microsoft Entra ID."
  default     = null

  validation {
    condition     = var.web_oidc_issuer_url == null || can(regex("^https://\\S+$", var.web_oidc_issuer_url))
    error_message = "The web_oidc_issuer_url must be an https:// URL."
  }
}

variable "web_oidc_scopes" {
  type        = list(string)
  description = "Scopes the Web UI requests, overriding the preset."
  default     = null
}

variable "web_oidc_client_secret_arn" {
  type        = string
  description = "Secrets Manager secret (JSON) holding the OIDC client ID and client secret, synced through External Secrets."
  default     = null

  validation {
    condition     = var.web_oidc_client_secret_arn == null || can(regex("^arn:aws[a-z-]*:secretsmanager:", var.web_oidc_client_secret_arn))
    error_message = "The web_oidc_client_secret_arn must be a Secrets Manager secret ARN."
  }
}

variable "web_oidc_client_id_property" {
  type        = string
  description = "JSON key of the client ID in the secret."
  default     = "client_id"
  nullable    = false
}

variable "web_oidc_client_secret_property" {
  type        = string
  description = "JSON key of the client secret in the secret."
  default     = "client_secret"
  nullable    = false
}

variable "web_oidc_callback_url" {
  type        = string
  description = "Callback URL to register with the provider. When null, https://<Web UI host>/auth/sso/callback, from the Tailscale hostname and tailnet domain or the ingress host."
  default     = null

  validation {
    condition     = var.web_oidc_callback_url == null || can(regex("^https?://\\S+$", var.web_oidc_callback_url))
    error_message = "The web_oidc_callback_url must be an http(s) URL."
  }
}

################################################################################
# Web UI
################################################################################

variable "web_enabled" {
  type        = bool
  description = "Run the Temporal Web UI. Without web_oidc_enabled it has no sign-in: anyone who can reach it can read and act on every namespace."
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
