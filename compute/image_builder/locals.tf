################################################################################
# Local Values
################################################################################

locals {
  region = coalesce(var.region, data.aws_region.current.region)

  default_tags = {
    ManagedBy = "terraform"
    Module    = "compute/image_builder"
  }

  tags = merge(local.default_tags, var.tags)

  # The two actions that run a list of commands. Every other action is given
  # the inputs its own documentation describes.
  shell_component_actions = ["ExecuteBash", "ExecutePowerShell"]

  # A form leaves an unused field blank rather than null, so a blank string is
  # read as unset everywhere a caller may leave one.
  parent_image_input          = try(trimspace(var.parent_image), "") == "" ? null : trimspace(var.parent_image)
  parent_image_lookup_enabled = local.parent_image_input == null && var.parent_image_lookup != null
  parent_image                = local.parent_image_lookup_enabled ? data.aws_ami.parent[0].id : local.parent_image_input

  # An AMI id is the only form of parent image this account can describe. An
  # Image Builder ARN or an SSM parameter is resolved by the build service.
  parent_image_id = try(regex("^ami-[0-9a-f]+$", coalesce(local.parent_image, "-")), null)

  # A component says where its document comes from: assembled here from the
  # steps and parameters a caller described, taken verbatim from data, or
  # already in the account under arn. A caller that leaves source out is read
  # by what it filled in.
  component_sources = {
    for c in var.components : c.name => (
      c.source != null ? c.source :
      try(trimspace(c.arn), "") != "" ? "arn" :
      try(trimspace(c.data), "") != "" ? "document" :
      "steps"
    )
  }

  # Steps become an Image Builder component document. A shell action carries
  # its commands; every other action carries the inputs it was given. A phase
  # with no steps is left out, and so is an optional step field left blank.
  component_documents = {
    for c in var.components : c.name => yamlencode(merge(
      {
        name          = c.name
        schemaVersion = "1.0"
        phases = [
          for phase in [
            { name = "build", steps = c.build_steps },
            { name = "validate", steps = c.validate_steps },
            { name = "test", steps = c.test_steps },
            ] : {
            name = phase.name
            steps = [
              for step in phase.steps : merge(
                {
                  name   = step.name
                  action = step.action
                },
                # Every branch is JSON text so the conditional has one type;
                # decoding turns it back into what the document carries. An
                # action that takes no inputs, such as Reboot, contributes
                # nothing.
                jsondecode(
                  contains(local.shell_component_actions, step.action) ? jsonencode({ inputs = { commands = step.commands } }) :
                  try(trimspace(step.inputs_json), "") == "" ? "{}" :
                  jsonencode({ inputs = jsondecode(step.inputs_json) })
                ),
                step.on_failure == null ? {} : { onFailure = step.on_failure },
                step.timeout_seconds == null ? {} : { timeoutSeconds = step.timeout_seconds },
                step.max_attempts == null ? {} : { maxAttempts = step.max_attempts },
              )
            ]
          } if length(phase.steps) > 0
        ]
      },
      try(trimspace(c.description), "") == "" ? {} : { description = trimspace(c.description) },
      length(c.parameter_definitions) == 0 ? {} : {
        parameters = [
          for parameter in c.parameter_definitions : {
            (parameter.name) = merge(
              { type = parameter.type },
              parameter.default == null ? {} : { default = parameter.default },
              try(trimspace(parameter.description), "") == "" ? {} : { description = trimspace(parameter.description) },
            )
          }
        ]
      },
    )) if local.component_sources[c.name] == "steps"
  }

  components = [
    for c in var.components : merge(c, {
      source = local.component_sources[c.name]
      # A parameter's value is passed by the recipe rather than written into
      # the document, so changing one leaves the component it configures alone.
      parameters = merge(c.parameters, {
        for parameter in c.parameter_definitions : parameter.name => parameter.value
        if try(trimspace(parameter.value), "") != ""
      })
      data = local.component_sources[c.name] == "steps" ? local.component_documents[c.name] : (
        local.component_sources[c.name] == "document" ? c.data : null
      )
      arn = local.component_sources[c.name] == "arn" ? trimspace(c.arn) : null
    })
  ]

  user_data = try(trimspace(var.user_data), "") == "" ? null : var.user_data

  # Components this module creates, keyed by name. A component is immutable, so
  # each is named by a hash of everything that would force a new one: a changed
  # document is a new component beside the old, never an update in place.
  inline_components = {
    for c in local.components : c.name => merge(c, {
      hash = substr(sha256(jsonencode([c.data, c.platform, c.description, var.recipe_version])), 0, 8)
    }) if c.data != null
  }

  # A public image cannot be backed by an encrypted snapshot.
  root_volume_encrypted = var.root_volume == null ? null : coalesce(var.root_volume.encrypted, !var.public)

  # Every image inherits the parent image's snapshot encryption, and the account
  # setting encrypts each new volume whatever the recipe asks for. Both decide
  # at build time whether a public image can be published, so a public build is
  # cleared of them at plan time. Null snapshots mean a parent this account
  # cannot describe, which proves nothing either way.
  parent_image_snapshots = local.parent_image_lookup_enabled ? data.aws_ami.parent[0].block_device_mappings : try(data.aws_ami.parent_snapshot[0].block_device_mappings, null)
  parent_image_encrypted = local.parent_image_snapshots == null ? null : anytrue([for mapping in local.parent_image_snapshots : try(mapping.ebs["encrypted"], "false") == "true"])
  encrypting_regions     = sort([for region, setting in data.aws_ebs_encryption_by_default.current : region if setting.enabled])

  # The recipe is immutable too, and named the same way. The hash covers the
  # inputs rather than the component ARNs, which are unknown until apply.
  recipe_hash = substr(sha256(jsonencode({
    version           = var.recipe_version
    description       = var.description
    parent_image      = local.parent_image
    components        = [for c in local.components : [c.name, c.data, c.arn, c.platform, c.description, c.parameters]]
    user_data         = local.user_data
    working_directory = var.working_directory
    ssm_uninstall     = var.ssm_agent_uninstall_after_build
    root_volume       = var.root_volume
    encrypted         = local.root_volume_encrypted
  })), 0, 8)

  ami_name = coalesce(var.ami_name, "${var.name}-{{ imagebuilder:buildDate }}")

  all_regions = distinct(concat([local.region], var.distribution_regions))

  launch_permission_enabled = var.public || length(var.launch_account_ids) > 0 || length(var.launch_organization_arns) > 0

  # A notification needs somewhere to go and something to prove it came from
  # this account; without both it is not configured, not half-configured.
  notify_enabled = var.notify_url != "" && var.notify_header_value != ""

  # EventBridge and IAM both cap a name at 64 characters, and name may use all
  # 64 on its own. A name too long for its suffix keeps its readable head, and
  # a hash of the full name keeps two pipelines from sharing one.
  notify_names = {
    for key, full in {
      role        = "${var.name}-image-notify"
      connection  = "${var.name}-image-notify"
      destination = "${var.name}-image-notify"
      rule        = "${var.name}-image-available"
    } : key => length(full) <= 64 ? full : "${substr(full, 0, 55)}-${substr(sha256(full), 0, 8)}"
  }

  log_prefix = trim(var.log_prefix, "/")

  # An empty prefix puts the logs at the bucket root rather than under an empty
  # first path segment, so the policy has to grant the root too.
  log_key_prefix = local.log_prefix == "" ? "" : "${local.log_prefix}/"

  # IAM caps a role name at 64 characters and name may use all 64 on its own. A
  # name too long for the suffix keeps its readable head, and a hash of the full
  # name keeps two pipelines from sharing a role.
  instance_role_name_full = "${var.name}-image-builder"
  instance_role_name      = length(local.instance_role_name_full) <= 64 ? local.instance_role_name_full : "${substr(local.instance_role_name_full, 0, 55)}-${substr(sha256(local.instance_role_name_full), 0, 8)}"

  pipeline_execution_policy_name = "${var.name}-start-image-pipeline"

  # Image Builder names each image after the recipe it came from, lowercased,
  # and this module's recipe name ends in a content hash that moves.
  pipeline_image_arn = "arn:${data.aws_partition.current.partition}:imagebuilder:${local.region}:${data.aws_caller_identity.current.account_id}:image/${lower(var.name)}-*/*"

  # The wait covers the build, the tests and the distribution, so it has to
  # outlast the test phase it contains.
  build_timeout_minutes = coalesce(var.build_timeout_minutes, var.image_tests_timeout_minutes + 60)
}
