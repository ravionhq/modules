################################################################################
# General
################################################################################

variable "project_id" {
  type        = string
  description = "ID of the Google Cloud project that owns the managed zone."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "The project_id must be a valid Google Cloud project ID (6-30 characters, lowercase letters, numbers, and hyphens, starting with a letter)."
  }
}

variable "region" {
  type        = string
  description = "Region for the provider. Cloud DNS zones are global; this only sets the provider default."
  default     = null
}

variable "labels" {
  type        = map(string)
  description = "Labels to assign to the managed zone. Keys and values are lowercased and invalid characters are replaced with hyphens."
  default     = {}
}

################################################################################
# Managed zone
################################################################################

variable "zone_creation_enabled" {
  type        = bool
  description = "Create a new managed zone. Set to false to manage records in an existing zone named by zone_name."
  default     = true
}

variable "zone_name" {
  type        = string
  description = "Name of the managed zone resource (not the domain). Required when zone_creation_enabled is false; defaults to the domain with dots replaced by hyphens when creating."
  default     = null

  validation {
    condition     = var.zone_name == null || can(regex("^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", var.zone_name))
    error_message = "The zone_name must be 1-63 characters, start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "dns_name" {
  type        = string
  description = "Domain the zone serves, such as example.com. A trailing dot is added when missing. Required when zone_creation_enabled is true."
  default     = null

  validation {
    condition     = var.dns_name == null || can(regex("^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\\.)*[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\\.?$", var.dns_name))
    error_message = "The dns_name must be a valid domain name, such as example.com."
  }
}

variable "description" {
  type        = string
  description = "Description stored on the created managed zone."
  default     = "Managed in Ravion"
}

variable "record_force_destroy_enabled" {
  type        = bool
  description = "Delete all records, including ones not managed by Terraform, when the created zone is destroyed."
  default     = false
}

variable "private_zone_enabled" {
  type        = bool
  description = "Create a private zone visible only to the networks in private_visibility_networks instead of a public zone."
  default     = false
}

variable "private_visibility_networks" {
  type        = list(string)
  description = "VPC networks that can resolve the private zone, as network self links or IDs (projects/<project>/global/networks/<network>)."
  default     = []

  validation {
    condition     = alltrue([for network in var.private_visibility_networks : can(regex("projects/[^/]+/global/networks/[^/]+$", network))])
    error_message = "Each private_visibility_networks entry must be a network self link or ID ending in projects/<project>/global/networks/<network>."
  }
}

################################################################################
# Records
################################################################################

variable "records" {
  type = list(object({
    name    = string
    type    = string
    ttl     = optional(number, 300)
    rrdatas = optional(list(string), [])
    routing_policy = optional(object({
      type = string
      items = list(object({
        key     = string
        weight  = optional(number, 1)
        rrdatas = list(string)
      }))
    }))
  }))
  description = <<-EOT
    DNS record sets to create in the zone. name is "@" for the zone apex, a
    name relative to the zone (app), or a fully qualified name (app.example.com
    or app.example.com.).
    Standard records set rrdatas. Records with routing_policy set it instead:
    type WEIGHTED splits answers by item weight (key is a label, weight
    defaults to 1), and type GEO
    answers by the caller's nearest Google Cloud region (key is the region).
  EOT
  default     = []

  validation {
    condition     = alltrue([for record in var.records : contains(["A", "AAAA", "CAA", "CNAME", "DS", "HTTPS", "MX", "NAPTR", "NS", "PTR", "SOA", "SPF", "SRV", "SSHFP", "SVCB", "TLSA", "TXT"], record.type)])
    error_message = "Each record type must be a record type Cloud DNS supports, such as A, AAAA, CNAME, MX, or TXT."
  }

  validation {
    condition     = alltrue([for record in var.records : record.ttl >= 0])
    error_message = "Each record ttl must be 0 or greater."
  }

  validation {
    condition = alltrue([
      for record in var.records :
      record.routing_policy == null ? length(record.rrdatas) > 0 : length(record.rrdatas) == 0
    ])
    error_message = "Each record needs rrdatas, or a routing_policy and no rrdatas."
  }

  validation {
    condition = alltrue([
      for record in var.records :
      record.routing_policy == null || try(contains(["WEIGHTED", "GEO"], record.routing_policy.type) && length(record.routing_policy.items) > 0, false)
    ])
    error_message = "Each routing_policy type must be WEIGHTED or GEO, with at least one item."
  }

  validation {
    condition = alltrue([
      for record in var.records :
      record.routing_policy == null || try(record.routing_policy.type != "WEIGHTED" || alltrue([for item in record.routing_policy.items : item.weight >= 0]), false)
    ])
    error_message = "Each weight of a WEIGHTED routing_policy must be 0 or more."
  }

  validation {
    condition     = length(distinct([for record in var.records : "${record.name}|${record.type}"])) == length(var.records)
    error_message = "Each record name and type pair can only appear once; use a routing_policy for several answers."
  }
}

################################################################################
# DNSSEC
################################################################################

variable "dnssec_enabled" {
  type        = bool
  description = "Sign the public zone with DNSSEC. Google manages the signing keys."
  default     = false
}

variable "dnssec_non_existence" {
  type        = string
  description = "How DNSSEC proves a name does not exist: nsec3 (default, prevents zone walking) or nsec."
  default     = "nsec3"

  validation {
    condition     = contains(["nsec", "nsec3"], var.dnssec_non_existence)
    error_message = "The dnssec_non_existence must be nsec or nsec3."
  }
}

################################################################################
# Logging
################################################################################

variable "query_logging_enabled" {
  type        = bool
  description = "Log DNS queries to Cloud Logging. For a public zone this turns on zone logging. For a private zone it creates a DNS server policy with logging on the visibility networks; a network can have only one server policy."
  default     = false
}

variable "server_policy_name" {
  type        = string
  description = "Name of the DNS server policy created for private-zone query logging. Defaults to <zone name>-logging."
  default     = null

  validation {
    condition     = var.server_policy_name == null || can(regex("^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", var.server_policy_name))
    error_message = "The server_policy_name must be 1-63 characters, start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}
