variable "organization" {
  description = "PlanetScale organization slug."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.organization))
    error_message = "The organization must be a lowercase PlanetScale organization slug."
  }
}

variable "name" {
  description = "PlanetScale database name. This module owns the database and its branches."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?$", var.name))
    error_message = "The name must contain 1-64 lowercase letters, numbers, or hyphens, starting and ending with a letter or number."
  }
}

variable "region" {
  description = "PlanetScale region slug, such as us-east or eu-west; not an AWS region identifier."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.region))
    error_message = "The region must be a non-empty PlanetScale region slug."
  }
}

variable "cluster_size" {
  description = "Main keyspace cluster SKU. Changes resize the keyspace in place after bootstrap."
  type        = string
  default     = "PS_10"
  nullable    = false

  validation {
    condition     = can(regex("^PS_[0-9]+$", var.cluster_size))
    error_message = "The cluster_size must be a network-storage Vitess SKU such as PS_10 or PS_80."
  }
}

variable "deletion_protection_enabled" {
  description = "Protect the main branch against deletion. Disable and apply before destroying the stack."
  type        = bool
  default     = true
  nullable    = false
}

variable "safe_migrations_enabled" {
  description = "Require PlanetScale deploy requests for main-branch schema changes instead of direct DDL."
  type        = bool
  default     = true
  nullable    = false
}

variable "extra_replicas" {
  description = "Additional main-keyspace replicas beyond those included by PlanetScale."
  type        = number
  default     = 0
  nullable    = false

  validation {
    condition     = var.extra_replicas >= 0 && floor(var.extra_replicas) == var.extra_replicas
    error_message = "The extra_replicas must be a nonnegative integer."
  }
}

variable "vtgate" {
  description = "Optional main-branch VTGate overrides. Omitted fields retain PlanetScale defaults."
  type = object({
    size                   = optional(string)
    count                  = optional(number)
    autoscaling_enabled    = optional(bool)
    max_count              = optional(number)
    target_cpu_utilization = optional(number)
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for n in [var.vtgate.count, var.vtgate.max_count] : n == null ? true : n >= 1 && floor(n) == n
    ])
    error_message = "VTGate count and max_count must be positive integers."
  }

  validation {
    condition     = var.vtgate.target_cpu_utilization == null ? true : var.vtgate.target_cpu_utilization >= 1 && var.vtgate.target_cpu_utilization <= 100
    error_message = "VTGate target_cpu_utilization must be between 1 and 100."
  }
}

variable "application_password" {
  description = "Application credential settings. Defaults to a non-expiring read/write password; CIDRs restrict its source IPs."
  type = object({
    name  = optional(string, "application")
    role  = optional(string, "readwriter")
    cidrs = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["reader", "writer", "readwriter", "admin"], var.application_password.role)
    error_message = "Application role must be reader, writer, readwriter, or admin."
  }

  validation {
    condition     = alltrue([for cidr in var.application_password.cidrs : can(cidrhost(cidr, 0))])
    error_message = "Application CIDRs must be valid IPv4 or IPv6 CIDR ranges."
  }
}

variable "additional_passwords" {
  description = "Additional named credentials on the main branch, for readers or migration tooling. Passwords are sensitive outputs."
  type = map(object({
    role                  = optional(string, "reader")
    cidrs                 = optional(list(string), [])
    replica_enabled       = optional(bool, false)
    direct_vtgate_enabled = optional(bool, false)
    ttl                   = optional(number)
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([for name, password in var.additional_passwords :
      length(trimspace(name)) > 0 && contains(["reader", "writer", "readwriter", "admin"], password.role) &&
      alltrue([for cidr in password.cidrs : can(cidrhost(cidr, 0))]) &&
      (password.ttl == null ? true : password.ttl > 0 && floor(password.ttl) == password.ttl)
    ])
    error_message = "Additional passwords require a nonempty name, a supported role, valid CIDRs, and a positive integer TTL when provided."
  }
}

variable "additional_keyspaces" {
  description = "Additional main-branch keyspaces. Cluster size and extra replicas resize in place; changing shard count replaces a keyspace."
  type = map(object({
    cluster_size   = optional(string, "PS_10")
    shards         = optional(number, 1)
    extra_replicas = optional(number, 0)
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([for name, keyspace in var.additional_keyspaces :
      can(regex("^[a-zA-Z0-9_][a-zA-Z0-9_-]*$", name)) &&
      can(regex("^PS_[0-9]+$", keyspace.cluster_size)) &&
      keyspace.shards >= 1 && floor(keyspace.shards) == keyspace.shards &&
      keyspace.extra_replicas >= 0 && floor(keyspace.extra_replicas) == keyspace.extra_replicas
    ])
    error_message = "Keyspaces require a valid name, a PS_ SKU, a positive integer shard count, and a nonnegative integer extra replica count."
  }
}

variable "backup_policies" {
  description = "Additional named backup policies. Empty leaves PlanetScale's built-in backups unchanged; custom backups incur storage charges."
  type = map(object({
    target          = optional(string, "production")
    frequency_unit  = optional(string, "day")
    frequency_value = optional(number, 1)
    retention_unit  = optional(string, "day")
    retention_value = optional(number, 7)
    schedule_time   = optional(string, "03:00")
    schedule_day    = optional(number)
    schedule_week   = optional(number)
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([for name, policy in var.backup_policies :
      length(trimspace(name)) > 0 && contains(["production", "development"], policy.target) &&
      contains(["hour", "day", "week", "month"], policy.frequency_unit) &&
      contains(["hour", "day", "week", "month", "year"], policy.retention_unit) &&
      policy.frequency_value > 0 && floor(policy.frequency_value) == policy.frequency_value &&
      policy.retention_value > 0 && floor(policy.retention_value) == policy.retention_value &&
      can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", policy.schedule_time)) &&
      (policy.schedule_day == null ? true : policy.schedule_day >= 0 && policy.schedule_day <= 6 && floor(policy.schedule_day) == policy.schedule_day) &&
      (policy.schedule_week == null ? true : policy.schedule_week >= 0 && policy.schedule_week <= 3 && floor(policy.schedule_week) == policy.schedule_week)
    ])
    error_message = "Backup policies require valid units and target, positive integer frequency/retention, HH:MM time, day 0-6, and week 0-3."
  }
}
