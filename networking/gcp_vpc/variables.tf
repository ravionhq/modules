################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name prefix for all resources created by this module. Also the VPC network name."

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,28}[a-z0-9])?$", var.name))
    error_message = "The name must be 1-30 characters, start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number, so that generated resource names stay within GCP's 63 character limit."
  }
}

variable "project_id" {
  type        = string
  description = "ID of the Google Cloud project to create the network in."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "The project_id must be a valid Google Cloud project ID (6-30 characters, lowercase letters, numbers, and hyphens, starting with a letter)."
  }
}

variable "region" {
  type        = string
  description = "Primary Google Cloud region. The module creates a subnetwork, Cloud Router, and Cloud NAT here."

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "The region must be a Google Cloud region name, such as us-central1."
  }
}

variable "labels" {
  type        = map(string)
  description = "Labels to assign to all resources that support them. Keys and values are lowercased and invalid characters are replaced with hyphens."
  default     = {}
}

################################################################################
# Network
################################################################################

variable "network_cidr" {
  type        = string
  description = <<-EOT
    IPv4 range that every subnetwork, secondary range, and the Private Service
    Access range are carved from. It is split into 8 equal blocks: block N holds
    the ranges of the Nth region (primary region first), and the last block
    holds the Private Service Access range. With the default 10.0.0.0/12, the
    primary region gets 10.0.0.0/16 for GKE pods, 10.1.0.0/20 for the
    subnetwork, 10.1.16.0/20 for GKE services, and 10.1.32.0/23 for the
    proxy-only subnetwork. Private Service Access gets 10.14.0.0/16.
  EOT
  default     = "10.0.0.0/12"

  validation {
    condition     = can(cidrhost(var.network_cidr, 0)) && try(tonumber(split("/", var.network_cidr)[1]) >= 8 && tonumber(split("/", var.network_cidr)[1]) <= 14, false)
    error_message = "The network_cidr must be a valid IPv4 CIDR block with a prefix length between /8 and /14."
  }
}

variable "additional_regions" {
  type        = list(string)
  description = "Other regions to create a subnetwork, Cloud Router, and Cloud NAT in. Address blocks are assigned by position, so add new regions at the end; removing or reordering a region changes the ranges of the regions after it."
  default     = []

  validation {
    condition     = length(var.additional_regions) <= 5 && length(distinct(var.additional_regions)) == length(var.additional_regions)
    error_message = "The additional_regions list can hold at most 5 regions, without duplicates."
  }

  validation {
    condition     = !contains(var.additional_regions, var.region)
    error_message = "The additional_regions list must not contain the primary region."
  }

  validation {
    condition     = alltrue([for region in var.additional_regions : can(regex("^[a-z]+-[a-z]+[0-9]+$", region))])
    error_message = "Each additional region must be a Google Cloud region name, such as europe-west1."
  }
}

variable "routing_mode" {
  type        = string
  description = "Dynamic routing mode of the network. REGIONAL advertises Cloud Router routes only in their own region; GLOBAL advertises them in every region, which hybrid connectivity (VPN, Interconnect) across regions needs."
  default     = "REGIONAL"

  validation {
    condition     = contains(["REGIONAL", "GLOBAL"], var.routing_mode)
    error_message = "The routing_mode must be REGIONAL or GLOBAL."
  }
}

################################################################################
# Subnetworks
################################################################################

variable "subnetwork_secondary_ranges_enabled" {
  type        = bool
  description = "Add the pods and services secondary ranges that VPC-native GKE clusters use to each subnetwork. Reserving them costs nothing."
  default     = true
}

variable "private_google_access_enabled" {
  type        = bool
  description = "Let VMs without external IP addresses reach Google APIs and services (Cloud Storage, Artifact Registry, Secret Manager) without Cloud NAT."
  default     = true
}

variable "proxy_only_subnetwork_creation_enabled" {
  type        = bool
  description = "Create a proxy-only subnetwork in each region. Regional external and internal Application Load Balancers and proxy Network Load Balancers need one; the global external Application Load Balancer does not."
  default     = false
}

################################################################################
# Cloud NAT
################################################################################

variable "nat_enabled" {
  type        = bool
  description = "Create a Cloud Router and Cloud NAT in each region so VMs, GKE nodes, and Cloud Run Direct VPC egress without external IP addresses can reach the internet."
  default     = true
}

variable "nat_static_ip_count" {
  type        = number
  description = "Number of static external IP addresses the module reserves for Cloud NAT in each region. Set to 0 to let Google allocate and scale NAT addresses automatically; those addresses can change, so partners cannot allowlist them. Ignored for a region listed in nat_ip_self_links."
  default     = 1

  validation {
    condition     = var.nat_static_ip_count >= 0 && var.nat_static_ip_count <= 16 && floor(var.nat_static_ip_count) == var.nat_static_ip_count
    error_message = "The nat_static_ip_count must be a whole number between 0 and 16."
  }
}

variable "nat_ip_self_links" {
  type        = map(list(string))
  description = "Existing reserved external IP addresses for Cloud NAT, keyed by region, as address self links or IDs. Use this to keep NAT IP addresses stable when the network is recreated. A region listed here uses these addresses instead of reserving its own."
  default     = {}

  validation {
    condition     = alltrue([for region, addresses in var.nat_ip_self_links : length(addresses) > 0])
    error_message = "Each region in nat_ip_self_links must list at least one address."
  }
}

variable "nat_min_ports_per_vm" {
  type        = number
  description = "Minimum number of NAT source ports reserved for each VM. Raise it for workloads that open many concurrent connections to the same destination."
  default     = 64

  validation {
    condition     = var.nat_min_ports_per_vm >= 2 && var.nat_min_ports_per_vm <= 65536
    error_message = "The nat_min_ports_per_vm must be between 2 and 65536."
  }
}

variable "nat_logging_enabled" {
  type        = bool
  description = "Write Cloud NAT logs to Cloud Logging."
  default     = true
}

variable "nat_logging_filter" {
  type        = string
  description = "Which Cloud NAT events to log: ERRORS_ONLY (dropped connections), TRANSLATIONS_ONLY (successful connections), or ALL."
  default     = "ERRORS_ONLY"

  validation {
    condition     = contains(["ERRORS_ONLY", "TRANSLATIONS_ONLY", "ALL"], var.nat_logging_filter)
    error_message = "The nat_logging_filter must be ERRORS_ONLY, TRANSLATIONS_ONLY, or ALL."
  }
}

################################################################################
# Private Service Access
################################################################################

variable "private_service_access_enabled" {
  type        = bool
  description = "Reserve an internal range and connect it to Google's service producer network, so Cloud SQL, AlloyDB, Memorystore, and Filestore instances get private IP addresses in this network."
  default     = true
}

variable "private_service_access_deletion_policy" {
  type        = string
  description = <<-EOT
    What happens to the Private Service Access connection when it is removed.
    DELETE (default) deletes it, which fails while producers such as Cloud SQL
    still hold resources; Cloud SQL keeps them for several days after an
    instance is deleted. REMOVE_PEERING falls back to removing the VPC peering
    so the network can be destroyed; only use it once every instance that uses
    the connection is gone. ABANDON removes it from state only, and the peering
    left behind blocks deleting the network.
  EOT
  default     = "DELETE"

  validation {
    condition     = contains(["DELETE", "REMOVE_PEERING", "ABANDON"], var.private_service_access_deletion_policy)
    error_message = "The private_service_access_deletion_policy must be DELETE, REMOVE_PEERING, or ABANDON."
  }
}

################################################################################
# Flow Logs
################################################################################

variable "flow_logs_enabled" {
  type        = bool
  description = "Enable VPC Flow Logs on every subnetwork. Logs go to Cloud Logging."
  default     = true
}

variable "flow_logs_aggregation_interval" {
  type        = string
  description = "How long flow records are aggregated before they are logged."
  default     = "INTERVAL_5_SEC"

  validation {
    condition     = contains(["INTERVAL_5_SEC", "INTERVAL_30_SEC", "INTERVAL_1_MIN", "INTERVAL_5_MIN", "INTERVAL_10_MIN", "INTERVAL_15_MIN"], var.flow_logs_aggregation_interval)
    error_message = "The flow_logs_aggregation_interval must be one of INTERVAL_5_SEC, INTERVAL_30_SEC, INTERVAL_1_MIN, INTERVAL_5_MIN, INTERVAL_10_MIN, or INTERVAL_15_MIN."
  }
}

variable "flow_logs_sampling" {
  type        = number
  description = "Fraction of flows to log, from 0 (exclusive) to 1. Lower values cut Cloud Logging costs."
  default     = 0.5

  validation {
    condition     = var.flow_logs_sampling > 0 && var.flow_logs_sampling <= 1
    error_message = "The flow_logs_sampling must be greater than 0 and at most 1."
  }
}

################################################################################
# Firewall
################################################################################

variable "firewall_internal_ingress_enabled" {
  type        = bool
  description = "Allow all ingress traffic from this network's own subnetwork, secondary, and proxy-only ranges. GCP denies ingress by default, and modules create their own rules for the traffic they need, so leave this off unless workloads talk to each other on ports no module opens."
  default     = false
}

variable "firewall_rules" {
  type = map(object({
    description             = optional(string)
    direction               = optional(string, "INGRESS")
    action                  = optional(string, "allow")
    priority                = optional(number, 1000)
    protocol                = optional(string, "tcp")
    ports                   = optional(list(string), [])
    source_ranges           = optional(list(string), [])
    destination_ranges      = optional(list(string), [])
    source_tags             = optional(list(string), [])
    source_service_accounts = optional(list(string), [])
    target_tags             = optional(list(string), [])
    target_service_accounts = optional(list(string), [])
    logging_enabled         = optional(bool, false)
  }))
  description = <<-EOT
    Extra VPC firewall rules, keyed by a short name that becomes part of the
    rule name (<name>-<key>). Each rule allows or denies one protocol on the
    listed ports (all ports when empty) and targets instances by network tag or
    service account (all instances when both are empty). For example, IAP TCP
    forwarding for SSH needs an INGRESS rule from 35.235.240.0/20 on tcp port 22.
  EOT
  default     = {}

  validation {
    condition     = alltrue([for key, rule in var.firewall_rules : can(regex("^[a-z]([a-z0-9-]{0,24}[a-z0-9])?$", key))])
    error_message = "Each firewall_rules key must be 1-26 characters, start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }

  validation {
    condition     = alltrue([for rule in values(var.firewall_rules) : contains(["INGRESS", "EGRESS"], rule.direction) && contains(["allow", "deny"], rule.action)])
    error_message = "Each firewall rule direction must be INGRESS or EGRESS, and its action must be allow or deny."
  }

  validation {
    condition     = alltrue([for rule in values(var.firewall_rules) : contains(["tcp", "udp", "icmp", "esp", "ah", "sctp", "ipip", "all"], rule.protocol)])
    error_message = "Each firewall rule protocol must be one of tcp, udp, icmp, esp, ah, sctp, ipip, or all."
  }

  validation {
    condition     = alltrue([for rule in values(var.firewall_rules) : length(rule.ports) == 0 || contains(["tcp", "udp", "sctp"], rule.protocol)])
    error_message = "Firewall rule ports can only be set for the tcp, udp, and sctp protocols."
  }

  validation {
    condition     = alltrue([for rule in values(var.firewall_rules) : rule.priority >= 0 && rule.priority <= 65535])
    error_message = "Each firewall rule priority must be between 0 and 65535."
  }

  validation {
    condition = alltrue([
      for rule in values(var.firewall_rules) :
      rule.direction == "INGRESS"
      ? length(rule.source_ranges) + length(rule.source_tags) + length(rule.source_service_accounts) > 0 && length(rule.destination_ranges) == 0
      : length(rule.destination_ranges) > 0 && length(rule.source_tags) + length(rule.source_service_accounts) == 0
    ])
    error_message = "An INGRESS firewall rule needs source_ranges, source_tags, or source_service_accounts and no destination_ranges. An EGRESS rule needs destination_ranges and no source tags or service accounts."
  }

  validation {
    condition     = alltrue([for rule in values(var.firewall_rules) : length(rule.target_tags) == 0 || length(rule.target_service_accounts) == 0])
    error_message = "A firewall rule can target network tags or service accounts, not both."
  }
}

################################################################################
# VPC Network Peering
################################################################################

variable "network_peerings" {
  type = map(object({
    peer_network         = string
    export_custom_routes = optional(bool, false)
    import_custom_routes = optional(bool, false)
  }))
  description = <<-EOT
    VPC Network Peering connections from this network, keyed by a short name.
    peer_network is the peer network's self link or ID
    (projects/<project>/global/networks/<network>). The peering only becomes
    ACTIVE once the peer network creates the matching peering back to this
    network; this module cannot manage the peer side.
  EOT
  default     = {}

  validation {
    condition     = alltrue([for key, peering in var.network_peerings : can(regex("^[a-z]([a-z0-9-]{0,24}[a-z0-9])?$", key))])
    error_message = "Each network_peerings key must be 1-26 characters, start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }

  validation {
    condition     = alltrue([for peering in values(var.network_peerings) : can(regex("projects/[^/]+/global/networks/[^/]+$", peering.peer_network))])
    error_message = "Each peer_network must be a network self link or ID ending in projects/<project>/global/networks/<network>."
  }
}
