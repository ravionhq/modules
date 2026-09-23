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
      # A parameter's value is passed by each build's recipe rather than
      # written into the document, so changing one leaves the component it
      # configures alone.
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

  # Components this module creates, keyed by name. A component is immutable, so
  # each is named by a hash of everything that would force a new one: a changed
  # document is a new component beside the old, never an update in place.
  inline_components = {
    for c in local.components : c.name => merge(c, {
      hash = substr(sha256(jsonencode([c.data, c.platform, c.description, var.component_version])), 0, 8)
    }) if c.data != null
  }

  # Every component this module creates or references, in run order, with its
  # real ARN regardless of source and the parameter values each build passes
  # it unless the deploy overrides them.
  component_refs = [
    for c in local.components : {
      name       = c.name
      arn        = c.arn != null ? c.arn : aws_imagebuilder_component.this[c.name].arn
      parameters = c.parameters
    }
  ]

  ami_name = coalesce(var.ami_name, "${var.name}-{{ imagebuilder:buildDate }}")

  log_prefix = trim(var.log_prefix, "/")

  # An empty prefix puts the logs at the bucket root rather than under an empty
  # first path segment, so the policy has to grant the root too.
  log_key_prefix = local.log_prefix == "" ? "" : "${local.log_prefix}/"

  # IAM caps a role name at 64 characters and name may use all 64 on its own. A
  # name too long for the suffix keeps its readable head, and a hash of the full
  # name keeps two modules from sharing a role.
  instance_role_name_full = "${var.name}-image-builder"
  instance_role_name      = length(local.instance_role_name_full) <= 64 ? local.instance_role_name_full : "${substr(local.instance_role_name_full, 0, 55)}-${substr(sha256(local.instance_role_name_full), 0, 8)}"
}
