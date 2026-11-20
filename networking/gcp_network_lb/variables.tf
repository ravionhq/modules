################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name prefix for all resources created by this module."

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,40}[a-z0-9])?$", var.name))
    error_message = "The name must be 1-42 characters, start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "project_id" {
  type        = string
  description = "ID of the Google Cloud project to create the load balancer in."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "The project_id must be a valid Google Cloud project ID."
  }
}

variable "region" {
  type        = string
  description = "Region of the load balancer and its backends."

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "The region must be a Google Cloud region name, such as us-central1."
  }
}

variable "labels" {
  type        = map(string)
  description = "Labels to assign to resources that support them. Keys and values are lowercased and invalid characters are replaced with hyphens."
  default     = {}
}

################################################################################
# Load balancer
################################################################################

variable "internal_load_balancer_enabled" {
  type        = bool
  description = "Create an internal passthrough Network Load Balancer reachable only from the VPC network, instead of an external one."
  default     = false
}

variable "network" {
  type        = string
  description = "Self link or ID of the VPC network of the backends. Used for firewall rules, and for the forwarding rule of an internal load balancer."

  validation {
    condition     = can(regex("projects/[^/]+/global/networks/[^/]+$", var.network))
    error_message = "The network must be a network self link or ID ending in projects/<project>/global/networks/<network>."
  }
}

variable "subnetwork" {
  type        = string
  description = "Self link or ID of the subnetwork the internal load balancer's IP address comes from. Required when internal_load_balancer_enabled is true."
  default     = null

  validation {
    condition     = var.subnetwork == null || can(regex("projects/[^/]+/regions/[^/]+/subnetworks/[^/]+$", var.subnetwork))
    error_message = "The subnetwork must be a subnetwork self link or ID ending in projects/<project>/regions/<region>/subnetworks/<subnetwork>."
  }
}

variable "protocol" {
  type        = string
  description = "Protocol the load balancer forwards: TCP, UDP, or L3_DEFAULT (TCP, UDP, ICMP, and other IP protocols on all ports)."
  default     = "TCP"

  validation {
    condition     = contains(["TCP", "UDP", "L3_DEFAULT"], var.protocol)
    error_message = "The protocol must be TCP, UDP, or L3_DEFAULT."
  }
}

variable "ports" {
  type        = list(string)
  description = "Up to 5 ports or port ranges (such as 443 or 8000-8100) the forwarding rule accepts. Empty forwards all ports. Must be empty for L3_DEFAULT."
  default     = []

  validation {
    condition     = length(var.ports) <= 5 && alltrue([for port in var.ports : can(regex("^[0-9]{1,5}(-[0-9]{1,5})?$", port))])
    error_message = "The ports list can hold at most 5 ports or port ranges, such as 443 or 8000-8100."
  }

  validation {
    condition     = var.protocol != "L3_DEFAULT" || length(var.ports) == 0
    error_message = "The ports list must be empty when protocol is L3_DEFAULT."
  }
}

variable "ip_address_creation_enabled" {
  type        = bool
  description = "Reserve a static IP address for the load balancer, so it survives replacing the forwarding rule. Set to false to use ip_address or an ephemeral address."
  default     = true
}

variable "ip_address" {
  type        = string
  description = "Existing reserved IP address (the address itself or its self link) to use when ip_address_creation_enabled is false. Null uses an ephemeral address."
  default     = null
}

variable "network_tier" {
  type        = string
  description = "Network tier of an external load balancer. PREMIUM routes over Google's network; STANDARD costs less and uses the public internet."
  default     = "PREMIUM"

  validation {
    condition     = contains(["PREMIUM", "STANDARD"], var.network_tier)
    error_message = "The network_tier must be PREMIUM or STANDARD."
  }
}

variable "global_access_enabled" {
  type        = bool
  description = "Let clients in any region reach an internal load balancer. Without it only clients in the load balancer's region can."
  default     = false
}

################################################################################
# Backends
################################################################################

variable "backends" {
  type = list(object({
    group    = string
    failover = optional(bool, false)
  }))
  description = "Instance groups or zonal network endpoint groups (GCE_VM_IP) behind the load balancer, as self links or IDs. failover marks a backend that only serves when the primary backends are unhealthy (internal load balancers only)."
  default     = []
}

variable "session_affinity" {
  type        = string
  description = "How connections from the same client are kept on one backend."
  default     = "NONE"

  validation {
    condition     = contains(["NONE", "CLIENT_IP", "CLIENT_IP_PROTO", "CLIENT_IP_PORT_PROTO"], var.session_affinity)
    error_message = "The session_affinity must be NONE, CLIENT_IP, CLIENT_IP_PROTO, or CLIENT_IP_PORT_PROTO."
  }
}

variable "connection_draining_timeout_seconds" {
  type        = number
  description = "Seconds existing connections may continue after a backend is removed."
  default     = 300

  validation {
    condition     = var.connection_draining_timeout_seconds >= 0 && var.connection_draining_timeout_seconds <= 3600
    error_message = "The connection_draining_timeout_seconds must be between 0 and 3600."
  }
}

variable "health_check" {
  type = object({
    protocol            = optional(string, "TCP")
    port                = number
    request_path        = optional(string, "/")
    interval_seconds    = optional(number, 10)
    timeout_seconds     = optional(number, 5)
    healthy_threshold   = optional(number, 2)
    unhealthy_threshold = optional(number, 3)
  })
  description = "Health check for the backends. UDP cannot be health checked directly, so UDP backends need a TCP, HTTP, or HTTPS check on some port."

  validation {
    condition     = contains(["TCP", "HTTP", "HTTPS"], var.health_check.protocol)
    error_message = "The health_check protocol must be TCP, HTTP, or HTTPS."
  }

  validation {
    condition     = var.health_check.port >= 1 && var.health_check.port <= 65535
    error_message = "The health_check port must be between 1 and 65535."
  }

  validation {
    condition     = var.health_check.timeout_seconds <= var.health_check.interval_seconds
    error_message = "The health_check timeout_seconds must not exceed interval_seconds."
  }
}

################################################################################
# Firewall
################################################################################

variable "firewall_creation_enabled" {
  type        = bool
  description = "Create firewall rules that let Google health checkers and clients reach the backends. Passthrough load balancers keep the client's source IP, so backends see client traffic directly."
  default     = true
}

variable "ingress_source_ranges" {
  type        = list(string)
  description = "IPv4 ranges allowed to reach the backends through the load balancer."
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for cidr in var.ingress_source_ranges : can(cidrhost(cidr, 0))])
    error_message = "All ingress_source_ranges must be valid IPv4 CIDR blocks."
  }
}

variable "target_tags" {
  type        = list(string)
  description = "Network tags of the backend instances the firewall rules apply to. Set this or target_service_accounts; with neither, the rules apply to every instance in the network."
  default     = []
}

variable "target_service_accounts" {
  type        = list(string)
  description = "Service account emails of the backend instances the firewall rules apply to. Cannot be combined with target_tags."
  default     = []

  validation {
    condition     = length(var.target_service_accounts) == 0 || length(var.target_tags) == 0
    error_message = "Set target_tags or target_service_accounts, not both."
  }
}

################################################################################
# Logging
################################################################################

variable "logging_enabled" {
  type        = bool
  description = "Write connection logs for the load balancer to Cloud Logging."
  default     = false
}

variable "logging_sample_rate" {
  type        = number
  description = "Fraction of connections to log, from 0 to 1."
  default     = 1

  validation {
    condition     = var.logging_sample_rate >= 0 && var.logging_sample_rate <= 1
    error_message = "The logging_sample_rate must be between 0 and 1."
  }
}
