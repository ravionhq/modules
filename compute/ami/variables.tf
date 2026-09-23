################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name of the configurations, and the prefix of every other resource this module creates."

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{1,63}$", var.name))
    error_message = "The name must be 2-64 letters, digits, hyphens or underscores, starting with a letter or digit."
  }
}

variable "description" {
  type        = string
  description = "Description stored on the infrastructure and distribution configurations."
  default     = null
}

variable "region" {
  type        = string
  description = "Region images are built in. Defaults to the provider's region."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to resources."
  default     = {}
}

################################################################################
# Parent image
################################################################################

variable "parent_image" {
  type        = string
  description = "Image each build starts from: an AMI id, an Image Builder image ARN, or an SSM parameter as ssm:<name>. Leave null to look one up with parent_image_lookup."
  default     = null
}

variable "parent_image_lookup" {
  type = object({
    owners       = list(string)
    name         = string
    architecture = optional(string, "x86_64")
  })
  description = "Looks the parent image up as the newest AMI in the build region matching an owner and a name pattern. The parent_image output reports the match at apply time. Ignored when parent_image is set."
  default     = null

  validation {
    condition     = var.parent_image_lookup == null || length(try(var.parent_image_lookup.owners, [])) > 0
    error_message = "The parent_image_lookup.owners must name at least one owner."
  }

  validation {
    condition     = var.parent_image_lookup == null || contains(["x86_64", "arm64"], try(var.parent_image_lookup.architecture, "x86_64"))
    error_message = "The parent_image_lookup.architecture must be x86_64 or arm64."
  }
}

################################################################################
# Components
################################################################################

variable "component_version" {
  type        = string
  description = "Semantic version of the components this module creates. Components are immutable, so this module names each by a hash of its content; the version never has to change for an apply to succeed."
  default     = "1.0.0"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.component_version))
    error_message = "The component_version must look like 1.0.0."
  }
}

variable "components" {
  type = list(object({
    name        = string
    source      = optional(string)
    data        = optional(string)
    arn         = optional(string)
    description = optional(string)
    platform    = optional(string, "Linux")
    parameters  = optional(map(string), {})
    parameter_definitions = optional(list(object({
      name        = string
      type        = optional(string, "string")
      default     = optional(string)
      description = optional(string)
      value       = optional(string)
    })), [])
    build_steps = optional(list(object({
      name            = string
      action          = optional(string, "ExecuteBash")
      commands        = optional(list(string), [])
      inputs_json     = optional(string)
      on_failure      = optional(string)
      timeout_seconds = optional(number)
      max_attempts    = optional(number)
    })), [])
    validate_steps = optional(list(object({
      name            = string
      action          = optional(string, "ExecuteBash")
      commands        = optional(list(string), [])
      inputs_json     = optional(string)
      on_failure      = optional(string)
      timeout_seconds = optional(number)
      max_attempts    = optional(number)
    })), [])
    test_steps = optional(list(object({
      name            = string
      action          = optional(string, "ExecuteBash")
      commands        = optional(list(string), [])
      inputs_json     = optional(string)
      on_failure      = optional(string)
      timeout_seconds = optional(number)
      max_attempts    = optional(number)
    })), [])
  }))
  description = "Components each build runs, in order. Each is created here from the steps it describes (source steps), created here from a component document given verbatim (source document), or referenced by ARN (source arn) — an AWS-managed component or one that already exists. A steps component names its parameters in parameter_definitions and its work in build_steps, validate_steps and test_steps; the module writes the document. Parameter values are passed to the component by each build's recipe, so a value can change without changing the document. A caller that leaves source out is read by whether it filled in arn, data, or steps."

  validation {
    condition     = length(var.components) > 0
    error_message = "The components must name at least one component."
  }

  validation {
    condition = alltrue([
      for c in var.components :
      c.source == "steps" ? length(c.build_steps) + length(c.validate_steps) + length(c.test_steps) > 0 :
      c.source == "document" ? try(trimspace(c.data), "") != "" :
      c.source == "arn" ? try(trimspace(c.arn), "") != "" :
      (try(trimspace(c.data), "") == "") != (try(trimspace(c.arn), "") == "")
    ])
    error_message = "Each component must describe steps, set data, or set arn, matching the source it names."
  }

  validation {
    condition     = alltrue([for c in var.components : c.source == null || contains(["steps", "document", "arn"], coalesce(c.source, "steps"))])
    error_message = "Each component source must be steps, document or arn."
  }

  validation {
    condition = alltrue(flatten([
      for c in var.components : [
        for step in concat(c.build_steps, c.validate_steps, c.test_steps) :
        contains(["ExecuteBash", "ExecutePowerShell"], step.action) ? length(step.commands) > 0 : (
          try(trimspace(step.inputs_json), "") == "" || can(jsondecode(step.inputs_json))
        )
      ]
    ]))
    error_message = "Each ExecuteBash or ExecutePowerShell step must list commands, and every other step must leave inputs_json blank or set it to valid JSON."
  }

  validation {
    condition = alltrue(flatten([
      for c in var.components : [
        for step in concat(c.build_steps, c.validate_steps, c.test_steps) :
        step.on_failure == null || contains(["Abort", "Continue", "Ignore"], coalesce(step.on_failure, "Abort"))
      ]
    ]))
    error_message = "Each step on_failure must be Abort, Continue or Ignore."
  }

  validation {
    condition = alltrue([
      for c in var.components : alltrue([
        for phase in [c.build_steps, c.validate_steps, c.test_steps] :
        length(distinct([for step in phase : step.name])) == length(phase)
      ])
    ])
    error_message = "Step names must be unique within a phase."
  }

  validation {
    condition = alltrue(flatten([
      for c in var.components : [
        for parameter in c.parameter_definitions :
        contains(["string", "integer", "boolean", "stringList"], parameter.type)
      ]
    ]))
    error_message = "Each component parameter type must be string, integer, boolean or stringList."
  }

  validation {
    condition     = length(distinct([for c in var.components : c.name])) == length(var.components)
    error_message = "Component names must be unique."
  }

  validation {
    condition     = alltrue([for c in var.components : can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,39}$", c.name))])
    error_message = "Each component name must be 1-40 letters, digits, hyphens or underscores."
  }

  validation {
    condition     = alltrue([for c in var.components : contains(["Linux", "Windows", "macOS"], c.platform)])
    error_message = "Each component platform must be Linux, Windows or macOS."
  }
}

################################################################################
# Build infrastructure
################################################################################

variable "instance_types" {
  type        = list(string)
  description = "Instance types a build may run on, in order of preference. They must match the parent image's architecture."
  default     = ["m7i.large"]

  validation {
    condition     = length(var.instance_types) > 0
    error_message = "The instance_types must name at least one instance type."
  }
}

variable "subnet_id" {
  type        = string
  description = "Subnet the build instance launches in. It needs outbound access to Systems Manager, Image Builder, S3 and whatever the components download. Null uses the default VPC."
  default     = null
}

variable "security_group_ids" {
  type        = list(string)
  description = "Security groups for the build instance. Required when subnet_id is set."
  default     = []
}

variable "terminate_instance_on_failure" {
  type        = bool
  description = "Terminate the build instance when a build fails. Turn off to keep it for debugging."
  default     = true
}

variable "instance_managed_policy_arns" {
  type        = list(string)
  description = "Managed policies attached to the build instance's role, beyond the two Image Builder needs."
  default     = []
}

variable "instance_policy_json" {
  type        = string
  description = "Inline IAM policy for the build instance's role, as JSON — what the components need to reach, such as read access to a release bucket."
  default     = null

  validation {
    condition     = var.instance_policy_json == null || can(jsondecode(var.instance_policy_json))
    error_message = "The instance_policy_json must be valid JSON."
  }
}

variable "log_bucket" {
  type        = string
  description = "S3 bucket the build logs are written to. The build instance is granted write access under log_prefix. Null keeps logs in CloudWatch only."
  default     = null
}

variable "log_prefix" {
  type        = string
  description = "Key prefix for build logs in log_bucket. An empty prefix writes them at the bucket root."
  default     = "image-builder"
}

################################################################################
# Distribution
################################################################################

variable "ami_name" {
  type        = string
  description = "Name of each image built. It must be unique per build, so it ends in {{ imagebuilder:buildDate }} unless you put that elsewhere. Defaults to <name>-{{ imagebuilder:buildDate }}."
  default     = null

  validation {
    condition     = var.ami_name == null || can(regex("\\{\\{\\s*imagebuilder:build(Date|Version)\\s*\\}\\}", var.ami_name))
    error_message = "The ami_name must contain {{ imagebuilder:buildDate }} or {{ imagebuilder:buildVersion }} so that every build gets its own name."
  }
}

variable "ami_description" {
  type        = string
  description = "Description stored on each image built, in the build region."
  default     = null
}

variable "ami_tags" {
  type        = map(string)
  description = "Tags written on each image built, in the build region. Tags are visible only to the owning account, even on a public image."
  default     = {}
}
