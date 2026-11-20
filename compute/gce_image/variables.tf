################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name prefix of the builder service account, the component bucket, and the builder VMs and images each deploy creates."

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,38}[a-z0-9])?$", var.name))
    error_message = "The name must be 1-40 characters, start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number, so that image and VM names stay within GCP's 63 character limit."
  }
}

variable "project_id" {
  type        = string
  description = "ID of the Google Cloud project images are built and stored in."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "The project_id must be a valid Google Cloud project ID (6-30 characters, lowercase letters, numbers, and hyphens, starting with a letter)."
  }
}

variable "region" {
  type        = string
  description = "Region of the component bucket and of the zone builds run in."

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "The region must be a Google Cloud region name, such as us-central1."
  }
}

variable "zone" {
  type        = string
  description = "Zone the builder and test VMs run in. Null picks the first zone of the region that is up."
  default     = null

  validation {
    condition     = var.zone == null ? true : can(regex("^${var.region}-[a-z]$", var.zone))
    error_message = "The zone must be a zone of the region, such as us-central1-a."
  }
}

variable "labels" {
  type        = map(string)
  description = "Labels to assign to all resources that support them, and to every image a deploy creates. Keys and values are lowercased and invalid characters are replaced with hyphens."
  default     = {}
}

variable "module_instance_id" {
  type        = string
  description = "Id of the Ravion module instance these resources belong to. Ravion sets it; null outside Ravion."
  default     = null
}

variable "enable_project_services" {
  type        = bool
  description = "Enable the Compute Engine, IAM and Cloud Storage APIs in the project. They are never disabled on destroy."
  default     = true
}

################################################################################
# Components
################################################################################

variable "components" {
  type = list(object({
    name        = string
    description = optional(string)
    parameter_definitions = optional(list(object({
      name        = string
      default     = optional(string)
      description = optional(string)
      value       = optional(string)
    })), [])
    build_steps = optional(list(object({
      name            = string
      commands        = list(string)
      timeout_seconds = optional(number)
    })), [])
    validate_steps = optional(list(object({
      name            = string
      commands        = list(string)
      timeout_seconds = optional(number)
    })), [])
    test_steps = optional(list(object({
      name            = string
      commands        = list(string)
      timeout_seconds = optional(number)
    })), [])
  }))
  description = "Components each build runs, in order. Each becomes one bash script in the component bucket: its build and validate steps run on the builder VM, its test steps on a VM booted from the finished image. Steps run their commands in order and stop at the first one that exits non-zero. Parameters reach the steps as environment variables of the same name; a deploy passes each parameter's value, or its own override, and a parameter neither sets falls back to its default."

  validation {
    condition     = length(var.components) > 0
    error_message = "The components must name at least one component."
  }

  validation {
    condition     = length(distinct([for c in var.components : c.name])) == length(var.components)
    error_message = "Each component must have a unique name."
  }

  validation {
    condition     = alltrue([for c in var.components : can(regex("^[a-z0-9]([a-z0-9_-]{0,38}[a-z0-9])?$", c.name))])
    error_message = "Each component name must be 1-40 lowercase letters, numbers, hyphens, or underscores, starting and ending with a letter or number."
  }

  validation {
    condition     = alltrue([for c in var.components : length(c.build_steps) + length(c.validate_steps) + length(c.test_steps) > 0])
    error_message = "Each component must have at least one step."
  }

  validation {
    condition = alltrue(flatten([
      for c in var.components : [
        for step in concat(c.build_steps, c.validate_steps, c.test_steps) :
        can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$", step.name)) && length(step.commands) > 0 && (step.timeout_seconds == null ? true : step.timeout_seconds > 0)
      ]
    ]))
    error_message = "Each step needs a name of 1-128 letters, numbers, hyphens, or underscores starting with a letter or number, at least one command, and a positive timeout_seconds when one is set."
  }

  validation {
    condition = alltrue([
      for c in var.components : alltrue([for phase in [c.build_steps, c.validate_steps, c.test_steps] : length(distinct([for step in phase : step.name])) == length(phase)])
    ])
    error_message = "Step names must be unique within each phase of a component."
  }

  validation {
    condition = alltrue(flatten([
      for c in var.components : [for p in c.parameter_definitions : can(regex("^[A-Za-z_][A-Za-z0-9_]{0,127}$", p.name))]
    ]))
    error_message = "Each parameter name must be a shell variable name: 1-128 letters, numbers, or underscores, not starting with a number."
  }

  validation {
    condition = alltrue([
      for c in var.components : length(distinct([for p in c.parameter_definitions : p.name])) == length(c.parameter_definitions)
    ])
    error_message = "Parameter names must be unique within each component."
  }
}

variable "component_retention_days" {
  type        = number
  description = "Days a replaced component script is kept, so a build that started before an apply can still download the version it was given."
  default     = 30

  validation {
    condition     = var.component_retention_days >= 1 && var.component_retention_days == floor(var.component_retention_days)
    error_message = "The component_retention_days must be a whole number of at least 1."
  }
}

################################################################################
# Builder
################################################################################

variable "network" {
  type        = string
  description = "Name of the VPC network the builder and test VMs attach to. Ignored when subnetwork is set."
  default     = "default"

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$", var.network))
    error_message = "The network must be a VPC network name."
  }
}

variable "subnetwork" {
  type        = string
  description = "Name of a subnetwork of the region for the builder and test VMs. Null attaches them to network, which must then be an auto mode network."
  default     = null

  validation {
    condition     = var.subnetwork == null ? true : can(regex("^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$", var.subnetwork))
    error_message = "The subnetwork must be a subnetwork name."
  }
}

variable "network_project_id" {
  type        = string
  description = "Project that owns network or subnetwork, for a Shared VPC. Null uses project_id."
  default     = null

  validation {
    condition     = var.network_project_id == null ? true : can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.network_project_id))
    error_message = "The network_project_id must be a valid Google Cloud project ID."
  }
}

variable "builder_roles" {
  type        = list(string)
  description = "Project roles granted to the builder service account, beyond writing logs and reading the component bucket."
  default     = []

  validation {
    condition     = alltrue([for role in var.builder_roles : can(regex("^(roles/[A-Za-z0-9_.]+|projects/[a-z][a-z0-9-]{4,28}[a-z0-9]/roles/[A-Za-z0-9_.]+|organizations/[0-9]+/roles/[A-Za-z0-9_.]+)$", role))])
    error_message = "Each builder role must be a predefined role (roles/...) or a custom role (projects/<project>/roles/... or organizations/<id>/roles/...)."
  }
}

variable "builder_bucket_readers" {
  type        = list(string)
  description = "Cloud Storage buckets the builder service account may read objects from, by name."
  default     = []

  validation {
    condition     = alltrue([for bucket in var.builder_bucket_readers : can(regex("^[a-z0-9][a-z0-9._-]{1,220}[a-z0-9]$", bucket))])
    error_message = "Each builder bucket must be a Cloud Storage bucket name, without gs://."
  }
}

variable "deployer_members" {
  type        = list(string)
  description = "Principals that start builds and so must act as the builder service account, such as serviceAccount:deployer@project.iam.gserviceaccount.com. Each is granted roles/iam.serviceAccountUser on that account only."
  default     = []

  validation {
    condition     = alltrue([for member in var.deployer_members : can(regex("^(serviceAccount|user|group|principal|principalSet):.+$", member))])
    error_message = "Each deployer member must be an IAM principal such as serviceAccount:name@project.iam.gserviceaccount.com."
  }
}
