# Image Builder module tests — run from module root: tofu test
#
# The module owns the build infrastructure only. It has no image recipe, image
# pipeline or image resource to assert on: each deploy creates its own recipe
# and build from the outputs checked below.

mock_provider "aws" {
  override_resource {
    target = aws_imagebuilder_component.this
    values = {
      arn = "arn:aws:imagebuilder:us-west-2:123456789012:component/test/1.0.0/1"
    }
  }

  override_resource {
    target = aws_imagebuilder_infrastructure_configuration.this
    values = {
      arn = "arn:aws:imagebuilder:us-west-2:123456789012:infrastructure-configuration/test"
    }
  }

  override_resource {
    target = aws_imagebuilder_distribution_configuration.this
    values = {
      arn = "arn:aws:imagebuilder:us-west-2:123456789012:distribution-configuration/test"
    }
  }

  override_data {
    target = data.aws_region.current
    values = {
      region = "us-west-2"
    }
  }

  override_data {
    target = data.aws_partition.current
    values = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  override_data {
    target = data.aws_ami.parent
    values = {
      id = "ami-0aaaaaaaaaaaaaaaa"
    }
  }
}

variables {
  name         = "test-image"
  parent_image = "ami-0123456789abcdef0"
  components = [
    {
      name = "provision"
      data = "name: provision\nschemaVersion: 1.0\nphases: []\n"
      parameters = {
        Version = "v1.2.3"
      }
    },
  ]
}

################################################################################
# Defaults — the build infrastructure a deploy builds against
################################################################################

run "defaults" {
  command = plan

  assert {
    condition     = aws_imagebuilder_infrastructure_configuration.this.name == "test-image"
    error_message = "The infrastructure configuration must be named after the module"
  }

  assert {
    condition     = aws_imagebuilder_infrastructure_configuration.this.instance_profile_name == aws_iam_role.instance.name
    error_message = "Builds must run as the build instance role"
  }

  assert {
    condition     = one(aws_imagebuilder_infrastructure_configuration.this.instance_metadata_options).http_tokens == "required"
    error_message = "The build instance must require IMDSv2"
  }

  assert {
    condition     = aws_iam_role.instance.name == "test-image-image-builder"
    error_message = "The build instance role must be named after the module, got ${aws_iam_role.instance.name}"
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.instance) == 2
    error_message = "The instance role must carry exactly the two Image Builder policies by default"
  }

  assert {
    condition     = length(aws_iam_role_policy.instance) == 0 && length(aws_iam_role_policy.logs) == 0
    error_message = "The instance role must carry no inline policy unless one is asked for"
  }

  # Pinned: a name that moves without its content moving would replace every
  # consumer's component on upgrade.
  assert {
    condition     = aws_imagebuilder_component.this["provision"].name == "test-image-provision-26a95f58"
    error_message = "A document component must be named by a stable content hash, got ${aws_imagebuilder_component.this["provision"].name}"
  }

  assert {
    condition     = output.parent_image == "ami-0123456789abcdef0"
    error_message = "The parent_image output must report the image given"
  }
}

################################################################################
# Distribution — the build region only, and never public
################################################################################

run "distribution_covers_the_build_region_only" {
  command = plan

  variables {
    ami_tags = { release = "v1.2.3" }
  }

  assert {
    condition     = length(aws_imagebuilder_distribution_configuration.this.distribution) == 1
    error_message = "The distribution configuration must cover the build region only, got ${length(aws_imagebuilder_distribution_configuration.this.distribution)} regions"
  }

  assert {
    condition     = one(aws_imagebuilder_distribution_configuration.this.distribution).region == "us-west-2"
    error_message = "The distribution configuration must cover the build region"
  }

  assert {
    condition     = length(one(one(aws_imagebuilder_distribution_configuration.this.distribution).ami_distribution_configuration).launch_permission) == 0
    error_message = "The distribution configuration must grant no launch permission; a deploy publishes explicitly"
  }

  assert {
    condition     = one(one(aws_imagebuilder_distribution_configuration.this.distribution).ami_distribution_configuration).name == "test-image-{{ imagebuilder:buildDate }}"
    error_message = "Each image must be named after the module and its build date by default"
  }

  assert {
    condition     = one(one(aws_imagebuilder_distribution_configuration.this.distribution).ami_distribution_configuration).ami_tags["release"] == "v1.2.3"
    error_message = "Each image must carry ami_tags"
  }

  assert {
    condition     = one(one(aws_imagebuilder_distribution_configuration.this.distribution).ami_distribution_configuration).ami_tags["ManagedBy"] == "terraform"
    error_message = "Each image must carry the module's own tags"
  }
}

run "a_region_moves_every_resource_with_it" {
  command = plan

  variables {
    region = "eu-west-1"
  }

  assert {
    condition     = output.region == "eu-west-1"
    error_message = "The region output must report the build region"
  }

  assert {
    condition     = one(aws_imagebuilder_distribution_configuration.this.distribution).region == "eu-west-1"
    error_message = "The distribution configuration must cover the build region"
  }

  assert {
    condition = (
      aws_imagebuilder_infrastructure_configuration.this.region == "eu-west-1" &&
      aws_imagebuilder_distribution_configuration.this.region == "eu-west-1" &&
      aws_imagebuilder_component.this["provision"].region == "eu-west-1"
    )
    error_message = "Every Image Builder resource must live in the build region"
  }
}

run "ami_name_must_be_unique_per_build" {
  command = plan

  variables {
    ami_name = "fixed-name"
  }

  expect_failures = [var.ami_name]
}

################################################################################
# Outputs a deploy builds from
################################################################################

run "outputs_feed_the_deploy" {
  command = plan

  assert {
    condition     = length(output.component_refs) == 1
    error_message = "component_refs must list every component a deploy's recipe runs"
  }

  assert {
    condition     = output.component_refs[0].name == "provision" && output.component_refs[0].arn == "arn:aws:imagebuilder:us-west-2:123456789012:component/test/1.0.0/1"
    error_message = "component_refs must carry each component's name and real ARN"
  }

  assert {
    condition     = output.component_refs[0].parameters == { Version = "v1.2.3" }
    error_message = "component_refs must carry each component's parameter values, the defaults a deploy's own parameters override"
  }

  assert {
    condition     = output.infrastructure_configuration_arn == "arn:aws:imagebuilder:us-west-2:123456789012:infrastructure-configuration/test"
    error_message = "infrastructure_configuration_arn must name the infrastructure configuration"
  }

  assert {
    condition     = output.distribution_configuration_arn == "arn:aws:imagebuilder:us-west-2:123456789012:distribution-configuration/test"
    error_message = "distribution_configuration_arn must name the distribution configuration"
  }

  assert {
    condition     = output.region == "us-west-2"
    error_message = "The region output must default to the provider's region"
  }
}

run "component_refs_keep_the_run_order_and_every_source" {
  command = plan

  variables {
    components = [
      {
        name       = "update"
        arn        = "arn:aws:imagebuilder:us-west-2:aws:component/update-linux/x.x.x"
        parameters = { Reboot = "true" }
      },
      {
        name        = "provision"
        source      = "steps"
        build_steps = [{ name = "Install", commands = ["echo installing"] }]
        parameter_definitions = [
          { name = "Version", default = "v1.0.0", value = "v1.2.3" },
        ]
      },
    ]
  }

  assert {
    condition     = [for ref in output.component_refs : ref.name] == ["update", "provision"]
    error_message = "component_refs must keep the order the components run in"
  }

  assert {
    condition     = output.component_refs[0].arn == "arn:aws:imagebuilder:us-west-2:aws:component/update-linux/x.x.x"
    error_message = "A referenced component must be passed by the ARN it was given"
  }

  assert {
    condition     = output.component_refs[0].parameters == { Reboot = "true" }
    error_message = "A referenced component must carry the parameter values it was given"
  }

  assert {
    condition     = output.component_refs[1].arn == "arn:aws:imagebuilder:us-west-2:123456789012:component/test/1.0.0/1"
    error_message = "A steps component must be passed by the ARN of the component created here"
  }

  assert {
    condition     = output.component_refs[1].parameters == { Version = "v1.2.3" }
    error_message = "A steps component must carry the values its parameter definitions give"
  }
}

################################################################################
# Parent image
################################################################################

run "parent_image_lookup" {
  command = plan

  variables {
    parent_image = null
    parent_image_lookup = {
      owners = ["123456789012"]
      name   = "base-*"
    }
  }

  assert {
    condition     = output.parent_image == "ami-0aaaaaaaaaaaaaaaa"
    error_message = "The parent_image output must report the image the lookup found"
  }
}

run "parent_image_is_required" {
  command = plan

  variables {
    parent_image = null
  }

  expect_failures = [output.parent_image]
}

run "a_blank_parent_image_is_unset" {
  command = plan

  variables {
    parent_image = "  "
  }

  expect_failures = [output.parent_image]
}

################################################################################
# Immutable components are renamed, not updated
################################################################################

run "changed_document_is_a_new_component" {
  command = plan

  variables {
    components = [
      {
        name = "provision"
        data = "name: provision\nschemaVersion: 1.0\nphases: [] # changed\n"
      },
    ]
  }

  assert {
    condition     = aws_imagebuilder_component.this["provision"].name != "test-image-provision-26a95f58"
    error_message = "A changed document must produce a differently named component"
  }
}

run "changed_parameter_value_keeps_the_same_component" {
  command = plan

  variables {
    components = [
      {
        name       = "provision"
        data       = "name: provision\nschemaVersion: 1.0\nphases: []\n"
        parameters = { Version = "v1.2.4" }
      },
    ]
  }

  assert {
    condition     = aws_imagebuilder_component.this["provision"].name == "test-image-provision-26a95f58"
    error_message = "A changed parameter value must not produce a new component"
  }

  assert {
    condition     = output.component_refs[0].parameters == { Version = "v1.2.4" }
    error_message = "A changed parameter value must reach the deploy through component_refs"
  }
}

run "changed_description_keeps_the_same_component" {
  command = plan

  variables {
    description = "Bakes the application image."
  }

  assert {
    condition     = aws_imagebuilder_component.this["provision"].name == "test-image-provision-26a95f58"
    error_message = "A changed module description must not produce a new component"
  }

  assert {
    condition     = aws_imagebuilder_infrastructure_configuration.this.description == "Bakes the application image." && aws_imagebuilder_distribution_configuration.this.description == "Bakes the application image."
    error_message = "The description must be stored on both configurations"
  }
}

run "changed_component_version_is_a_new_component" {
  command = plan

  variables {
    component_version = "1.0.1"
  }

  assert {
    condition     = aws_imagebuilder_component.this["provision"].name != "test-image-provision-26a95f58"
    error_message = "A changed component version must produce a differently named component"
  }

  assert {
    condition     = aws_imagebuilder_component.this["provision"].version == "1.0.1"
    error_message = "The component must carry component_version"
  }
}

################################################################################
# Components written from steps
################################################################################

run "steps_become_a_component_document" {
  command = plan

  variables {
    components = [
      {
        name        = "provision"
        source      = "steps"
        description = "Installs the runtime"
        parameter_definitions = [
          {
            name        = "Version"
            type        = "string"
            default     = "v1.0.0"
            description = "Release to install"
          },
        ]
        build_steps = [
          {
            name     = "Install"
            commands = ["set -euo pipefail", "echo installing"]
          },
        ]
        validate_steps = [
          {
            name       = "Check"
            commands   = ["test -x /usr/local/bin/app"]
            on_failure = "Continue"
          },
        ]
      },
    ]
  }

  assert {
    condition     = yamldecode(aws_imagebuilder_component.this["provision"].data).name == "provision"
    error_message = "The document must be named after the component"
  }

  assert {
    condition     = yamldecode(aws_imagebuilder_component.this["provision"].data).schemaVersion == "1.0"
    error_message = "The document must name the schema version Image Builder expects"
  }

  assert {
    condition     = yamldecode(aws_imagebuilder_component.this["provision"].data).description == "Installs the runtime"
    error_message = "A description must reach the document"
  }

  assert {
    condition     = [for phase in yamldecode(aws_imagebuilder_component.this["provision"].data).phases : phase.name] == ["build", "validate"]
    error_message = "A phase with no steps must be left out"
  }

  assert {
    condition     = yamldecode(aws_imagebuilder_component.this["provision"].data).phases[0].steps[0].action == "ExecuteBash"
    error_message = "A step must run its action"
  }

  assert {
    condition     = yamldecode(aws_imagebuilder_component.this["provision"].data).phases[0].steps[0].inputs.commands == ["set -euo pipefail", "echo installing"]
    error_message = "A shell step must carry its commands"
  }

  assert {
    condition     = yamldecode(aws_imagebuilder_component.this["provision"].data).phases[1].steps[0].onFailure == "Continue"
    error_message = "A step must carry the failure behaviour it was given"
  }

  assert {
    condition     = !can(yamldecode(aws_imagebuilder_component.this["provision"].data).phases[0].steps[0].onFailure)
    error_message = "A step must leave out what it was not given"
  }

  assert {
    condition     = yamldecode(aws_imagebuilder_component.this["provision"].data).parameters[0].Version.default == "v1.0.0"
    error_message = "A parameter must reach the document with its default"
  }

  assert {
    condition     = !can(yamldecode(aws_imagebuilder_component.this["provision"].data).parameters[0].Version.value)
    error_message = "A parameter's value belongs to the deploy's recipe, not the document"
  }
}

run "a_parameter_without_a_value_is_left_to_its_default" {
  command = plan

  variables {
    components = [
      {
        name   = "provision"
        source = "steps"
        parameter_definitions = [
          { name = "Version", default = "v1.0.0" },
        ]
        build_steps = [{ name = "Install", commands = ["echo installing"] }]
      },
    ]
  }

  assert {
    condition     = output.component_refs[0].parameters == {}
    error_message = "A parameter left without a value must not be passed to the deploy"
  }

  # Pinned so the next run can prove a value leaves this component alone.
  assert {
    condition     = aws_imagebuilder_component.this["provision"].name == "test-image-provision-89e1f3f7"
    error_message = "A steps component must be named by a stable content hash, got ${aws_imagebuilder_component.this["provision"].name}"
  }
}

run "a_parameter_value_reaches_the_deploy_over_the_same_component" {
  command = plan

  variables {
    components = [
      {
        name   = "provision"
        source = "steps"
        parameter_definitions = [
          { name = "Version", default = "v1.0.0", value = "v1.2.3" },
        ]
        build_steps = [{ name = "Install", commands = ["echo installing"] }]
      },
    ]
  }

  assert {
    condition     = output.component_refs[0].parameters == { Version = "v1.2.3" }
    error_message = "A parameter value must be passed to the deploy"
  }

  assert {
    condition     = aws_imagebuilder_component.this["provision"].name == "test-image-provision-89e1f3f7"
    error_message = "A parameter value must not change the component a deploy builds with"
  }
}

run "a_step_that_is_not_a_shell_carries_its_own_inputs" {
  command = plan

  variables {
    components = [
      {
        name   = "provision"
        source = "steps"
        build_steps = [
          {
            name        = "Fetch"
            action      = "S3Download"
            inputs_json = jsonencode([{ source = "s3://releases/app", destination = "/tmp/app" }])
          },
          {
            name            = "Install"
            commands        = ["install -m 0755 /tmp/app /usr/local/bin/app"]
            timeout_seconds = 600
            max_attempts    = 2
          },
          { name = "Restart", action = "Reboot" },
        ]
      },
    ]
  }

  assert {
    condition     = yamldecode(aws_imagebuilder_component.this["provision"].data).phases[0].steps[0].inputs[0].source == "s3://releases/app"
    error_message = "A non-shell step must carry the inputs its action documents"
  }

  assert {
    condition     = yamldecode(aws_imagebuilder_component.this["provision"].data).phases[0].steps[1].timeoutSeconds == 600
    error_message = "A step must carry its timeout"
  }

  assert {
    condition     = yamldecode(aws_imagebuilder_component.this["provision"].data).phases[0].steps[1].maxAttempts == 2
    error_message = "A step must carry its attempt count"
  }

  assert {
    condition     = !can(yamldecode(aws_imagebuilder_component.this["provision"].data).phases[0].steps[2].inputs)
    error_message = "An action that takes no inputs must carry none"
  }
}

run "a_changed_step_is_a_new_component" {
  command = plan

  variables {
    components = [
      {
        name   = "provision"
        source = "steps"
        parameter_definitions = [
          { name = "Version", default = "v1.0.0" },
        ]
        build_steps = [{ name = "Install", commands = ["echo installing something else"] }]
      },
    ]
  }

  assert {
    condition     = aws_imagebuilder_component.this["provision"].name != "test-image-provision-89e1f3f7"
    error_message = "A changed step must produce a differently named component"
  }
}

run "a_shell_step_needs_commands" {
  command = plan

  variables {
    components = [
      {
        name        = "provision"
        source      = "steps"
        build_steps = [{ name = "Install" }]
      },
    ]
  }

  expect_failures = [var.components]
}

run "steps_must_be_named_apart_within_a_phase" {
  command = plan

  variables {
    components = [
      {
        name   = "provision"
        source = "steps"
        build_steps = [
          { name = "Install", commands = ["echo one"] },
          { name = "Install", commands = ["echo two"] },
        ]
      },
    ]
  }

  expect_failures = [var.components]
}

################################################################################
# Referenced components and component validation
################################################################################

run "a_referenced_component_is_not_created" {
  command = plan

  variables {
    components = [
      {
        name = "update"
        arn  = "arn:aws:imagebuilder:us-west-2:aws:component/update-linux/x.x.x"
      },
    ]
  }

  assert {
    condition     = length(aws_imagebuilder_component.this) == 0
    error_message = "A referenced component must not be created"
  }

  assert {
    condition     = output.component_refs[0].arn == "arn:aws:imagebuilder:us-west-2:aws:component/update-linux/x.x.x"
    error_message = "A referenced component must be passed to the deploy by ARN"
  }
}

run "source_picks_between_a_stale_document_and_an_arn" {
  command = plan

  variables {
    components = [
      {
        name   = "update"
        source = "arn"
        data   = "name: stale\nschemaVersion: 1.0\nphases: []\n"
        arn    = "arn:aws:imagebuilder:us-west-2:aws:component/update-linux/x.x.x"
      },
    ]
  }

  assert {
    condition     = length(aws_imagebuilder_component.this) == 0
    error_message = "A component whose source is arn must not be created from a leftover document"
  }

  assert {
    condition     = output.component_refs[0].arn == "arn:aws:imagebuilder:us-west-2:aws:component/update-linux/x.x.x"
    error_message = "A component whose source is arn must be passed to the deploy by that ARN"
  }
}

run "component_needs_exactly_one_source" {
  command = plan

  variables {
    components = [{ name = "both", data = "x", arn = "arn:aws:imagebuilder:us-west-2:aws:component/x/1.0.0" }]
  }

  expect_failures = [var.components]
}

run "components_must_name_at_least_one" {
  command = plan

  variables {
    components = []
  }

  expect_failures = [var.components]
}

run "component_names_must_be_unique" {
  command = plan

  variables {
    components = [
      { name = "provision", data = "name: a\nschemaVersion: 1.0\nphases: []\n" },
      { name = "provision", data = "name: b\nschemaVersion: 1.0\nphases: []\n" },
    ]
  }

  expect_failures = [var.components]
}

################################################################################
# Build infrastructure
################################################################################

run "build_infrastructure_options" {
  command = plan

  variables {
    log_bucket                   = "example-logs"
    instance_policy_json         = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    instance_managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"]
    instance_types               = ["c7i.large", "m7i.large"]
    subnet_id                    = "subnet-0123456789abcdef0"
    security_group_ids           = ["sg-0123456789abcdef0"]
  }

  assert {
    condition     = one(one(aws_imagebuilder_infrastructure_configuration.this.logging).s3_logs).s3_bucket_name == "example-logs"
    error_message = "Logs must go to log_bucket"
  }

  assert {
    condition     = length(aws_iam_role_policy.logs) == 1 && length(aws_iam_role_policy.instance) == 1
    error_message = "The instance role must carry the log and component policies"
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.instance) == 3
    error_message = "The instance role must carry the extra managed policy beside the two Image Builder needs"
  }

  assert {
    condition     = aws_imagebuilder_infrastructure_configuration.this.instance_types == toset(["c7i.large", "m7i.large"])
    error_message = "Builds must run on the instance types given"
  }

  assert {
    condition     = aws_imagebuilder_infrastructure_configuration.this.subnet_id == "subnet-0123456789abcdef0" && aws_imagebuilder_infrastructure_configuration.this.security_group_ids == toset(["sg-0123456789abcdef0"])
    error_message = "Builds must launch in the subnet and security groups given"
  }
}

run "subnet_requires_security_groups" {
  command = plan

  variables {
    subnet_id = "subnet-0123456789abcdef0"
  }

  expect_failures = [aws_imagebuilder_infrastructure_configuration.this]
}

run "a_long_name_still_fits_an_iam_role_name" {
  command = plan

  variables {
    name = "application-image-builder-for-the-us-west-2-build-fleet-in-2026"
  }

  assert {
    condition     = length(aws_iam_role.instance.name) == 64
    error_message = "A name too long for the suffix must be truncated to the IAM limit, got ${aws_iam_role.instance.name}"
  }

  assert {
    condition     = startswith(aws_iam_role.instance.name, "application-image-builder-for-the-us-west-2-build-fleet")
    error_message = "A truncated role name must keep the head of the name, got ${aws_iam_role.instance.name}"
  }

  assert {
    condition     = aws_iam_instance_profile.instance.name == aws_iam_role.instance.name
    error_message = "The instance profile must carry the same name as the role"
  }
}

################################################################################
# Build logs
################################################################################

run "an_empty_log_prefix_writes_at_the_bucket_root" {
  command = plan

  variables {
    log_bucket = "example-logs"
    log_prefix = "/"
  }

  assert {
    condition     = jsondecode(one(aws_iam_role_policy.logs).policy).Statement[0].Resource == "arn:aws:s3:::example-logs/*"
    error_message = "An empty prefix must grant the bucket root, got ${jsondecode(one(aws_iam_role_policy.logs).policy).Statement[0].Resource}"
  }

  assert {
    condition     = one(one(aws_imagebuilder_infrastructure_configuration.this.logging).s3_logs).s3_key_prefix == null
    error_message = "An empty prefix must leave s3_key_prefix unset so Image Builder writes at the root"
  }
}

run "a_log_prefix_is_granted_and_written_under" {
  command = plan

  variables {
    log_bucket = "example-logs"
    log_prefix = "builds/"
  }

  assert {
    condition     = jsondecode(one(aws_iam_role_policy.logs).policy).Statement[0].Resource == "arn:aws:s3:::example-logs/builds/*"
    error_message = "The policy must grant exactly the prefix the logs are written under, got ${jsondecode(one(aws_iam_role_policy.logs).policy).Statement[0].Resource}"
  }

  assert {
    condition     = one(one(aws_imagebuilder_infrastructure_configuration.this.logging).s3_logs).s3_key_prefix == "builds"
    error_message = "Image Builder must write under the prefix the policy grants"
  }
}
