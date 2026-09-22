################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name of the pipeline, and the prefix of every other resource this module creates."

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{1,63}$", var.name))
    error_message = "The name must be 2-64 letters, digits, hyphens or underscores, starting with a letter or digit."
  }
}

variable "description" {
  type        = string
  description = "Description stored on the pipeline, the recipe and the configurations."
  default     = null
}

variable "region" {
  type        = string
  description = "Region the image is built in. Defaults to the provider's region."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to resources."
  default     = {}
}

################################################################################
# Recipe
################################################################################

variable "recipe_version" {
  type        = string
  description = "Semantic version of the recipe and of the components this module creates. Recipes and components are immutable, so this module names each by a hash of its content; the version never has to change for an apply to succeed."
  default     = "1.0.0"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.recipe_version))
    error_message = "The recipe_version must look like 1.0.0."
  }
}

variable "parent_image" {
  type        = string
  description = "Image the recipe builds on: an AMI id, an Image Builder image ARN, or an SSM parameter as ssm:<name>. Leave null to look one up with parent_image_lookup."
  default     = null
}

variable "parent_image_lookup" {
  type = object({
    owners       = list(string)
    name         = string
    architecture = optional(string, "x86_64")
  })
  description = "Looks the parent image up as the newest AMI in the build region matching an owner and a name pattern. The id is resolved at plan time, so an apply after the owner publishes a newer image produces a new recipe. Ignored when parent_image is set."
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
  description = "Components the recipe runs, in order. Each is created here from the steps it describes (source steps), created here from a component document given verbatim (source document), or referenced by ARN (source arn) — an AWS-managed component or one that already exists. A steps component names its parameters in parameter_definitions and its work in build_steps, validate_steps and test_steps; the module writes the document. Parameters are passed to the component by the recipe, so a value can change without changing the document. A caller that leaves source out is read by whether it filled in arn, data, or steps."

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

variable "user_data" {
  type        = string
  description = "User data the build instance launches with, in plain text. Supplying it replaces the script Image Builder would otherwise use to install the Systems Manager agent, so it must install the agent itself on a parent image that does not ship one."
  default     = null
}

variable "working_directory" {
  type        = string
  description = "Working directory for the build and test workflows. Null keeps the Image Builder default."
  default     = null
}

variable "ssm_agent_uninstall_after_build" {
  type        = bool
  description = "Remove the Systems Manager agent from the image when Image Builder installed it for the build. An agent the parent image or user_data installed is left alone."
  default     = true
}

variable "root_volume" {
  type = object({
    device_name = string
    size_gb     = number
    type        = optional(string, "gp3")
    iops        = optional(number)
    throughput  = optional(number)
    encrypted   = optional(bool)
    kms_key_id  = optional(string)
  })
  description = "Root volume of the build instance, which becomes the image's snapshot: its size is the smallest root volume an instance can launch the image with. Null keeps the parent image's mapping. Encryption defaults to on, and to off for a public image, which cannot be backed by an encrypted snapshot."
  default     = null

  validation {
    condition     = var.root_volume == null || try(var.root_volume.size_gb >= 1 && var.root_volume.size_gb <= 65536, false)
    error_message = "The root_volume.size_gb must be between 1 and 65536."
  }
}

################################################################################
# Build infrastructure
################################################################################

variable "instance_types" {
  type        = list(string)
  description = "Instance types the build may run on, in order of preference. They must match the parent image's architecture."
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

variable "create_pipeline_execution_policy" {
  type        = bool
  description = "Create a customer-managed IAM policy that starts this pipeline and reads the images it produces. Attach it to a deploy pipeline's role to build an image outside Terraform with `aws imagebuilder start-image-pipeline-execution`."
  default     = false
}

################################################################################
# Distribution
################################################################################

variable "ami_name" {
  type        = string
  description = "Name of each image produced. It must be unique per build, so it ends in {{ imagebuilder:buildDate }} unless you put that elsewhere. Defaults to <name>-{{ imagebuilder:buildDate }}."
  default     = null

  validation {
    condition     = var.ami_name == null || can(regex("\\{\\{\\s*imagebuilder:build(Date|Version)\\s*\\}\\}", var.ami_name))
    error_message = "The ami_name must contain {{ imagebuilder:buildDate }} or {{ imagebuilder:buildVersion }} so that every build gets its own name."
  }
}

variable "ami_description" {
  type        = string
  description = "Description stored on each image produced."
  default     = null
}

variable "ami_tags" {
  type        = map(string)
  description = "Tags written on each image produced, in every region. Tags are visible only to the owning account, even on a public image."
  default     = {}
}

variable "distribution_regions" {
  type        = list(string)
  description = "Regions the finished image is copied to, beyond the build region."
  default     = []

  validation {
    condition     = length(var.distribution_regions) == length(distinct(var.distribution_regions))
    error_message = "The distribution_regions must not contain duplicates."
  }
}

variable "public" {
  type        = bool
  description = "Make every image produced launchable by any AWS account."
  default     = false
}

variable "manage_image_block_public_access" {
  type        = bool
  description = "When public is true, turn off the account-wide block on public AMI sharing in the build region and every distribution region. The setting covers every image the account owns in those regions, not only the images this module builds, and destroying this module does not turn it back on: re-block it with `aws ec2 enable-image-block-public-access --image-block-public-access block-new-sharing --region <region>`. Left false, a public build fails in any region that still blocks sharing, and the account keeps the block."
  default     = false
}

variable "launch_account_ids" {
  type        = list(string)
  description = "AWS accounts granted launch permission on every image produced."
  default     = []

  validation {
    condition     = alltrue([for id in var.launch_account_ids : can(regex("^[0-9]{12}$", id))])
    error_message = "Each launch_account_ids entry must be a 12-digit AWS account id."
  }
}

variable "launch_organization_arns" {
  type        = list(string)
  description = "AWS Organizations granted launch permission on every image produced."
  default     = []
}

################################################################################
# Pipeline
################################################################################

variable "pipeline_enabled" {
  type        = bool
  description = "Whether the pipeline can run. A disabled pipeline keeps its configuration and ignores its schedule."
  default     = true
}

variable "schedule_expression" {
  type        = string
  description = "Cron expression the pipeline runs on, as cron(0 0 * * ? *). Null leaves it manual."
  default     = null
}

variable "schedule_start_condition" {
  type        = string
  description = "Whether a scheduled run always builds, or only when the parent image or a component using a wildcard version has an update."
  default     = "EXPRESSION_MATCH_AND_DEPENDENCY_UPDATES_AVAILABLE"

  validation {
    condition     = contains(["EXPRESSION_MATCH_ONLY", "EXPRESSION_MATCH_AND_DEPENDENCY_UPDATES_AVAILABLE"], var.schedule_start_condition)
    error_message = "The schedule_start_condition must be EXPRESSION_MATCH_ONLY or EXPRESSION_MATCH_AND_DEPENDENCY_UPDATES_AVAILABLE."
  }
}

variable "image_tests_enabled" {
  type        = bool
  description = "Launch a test instance from the new image and run the components' test phases. The test instance is driven through the Systems Manager agent, so turn this off for an image that does not start one on boot."
  default     = true
}

variable "image_tests_timeout_minutes" {
  type        = number
  description = "How long the test phase may run."
  default     = 60

  validation {
    condition     = var.image_tests_timeout_minutes >= 60 && var.image_tests_timeout_minutes <= 1440
    error_message = "The image_tests_timeout_minutes must be between 60 and 1440."
  }
}

variable "enhanced_image_metadata_enabled" {
  type        = bool
  description = "Collect the package list and other metadata from each image built."
  default     = true
}

variable "build_timeout_minutes" {
  type        = number
  description = "How long an apply waits for a build_on_apply build, covering the build, the tests and the distribution. Null allows an hour on top of image_tests_timeout_minutes."
  default     = null

  validation {
    condition     = var.build_timeout_minutes == null || try(var.build_timeout_minutes > var.image_tests_timeout_minutes, false)
    error_message = "The build_timeout_minutes must be greater than image_tests_timeout_minutes, which the build contains."
  }
}

variable "build_on_apply" {
  type        = bool
  description = "Build an image during apply, and again whenever the recipe changes. The apply waits for the build and its distribution, which commonly takes 20-60 minutes. Destroying the image record later leaves the AMIs in place."
  default     = false
}

################################################################################
# Build notification
################################################################################

variable "notify_url" {
  type        = string
  description = "HTTPS endpoint told when a build finishes and its images are distributed. Empty sends no notifications."
  default     = ""

  validation {
    condition     = var.notify_url == "" || startswith(var.notify_url, "https://")
    error_message = "The notify_url must be an https:// endpoint."
  }
}

variable "notify_header_name" {
  type        = string
  description = "Header the notification carries so the endpoint can authenticate it."
  default     = "X-Lambda-Secret"
}

variable "notify_header_value" {
  type        = string
  description = "Value of that header."
  default     = ""
  sensitive   = true
}
