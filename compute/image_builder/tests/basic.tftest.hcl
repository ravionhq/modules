# Image Builder module tests — run from module root: tofu test

mock_provider "aws" {
  override_resource {
    target = aws_imagebuilder_component.this
    values = {
      arn = "arn:aws:imagebuilder:us-west-2:123456789012:component/test/1.0.0/1"
    }
  }

  override_resource {
    target = aws_imagebuilder_image_recipe.this
    values = {
      arn = "arn:aws:imagebuilder:us-west-2:123456789012:image-recipe/test/1.0.0"
    }
  }

  override_resource {
    target = aws_imagebuilder_image_pipeline.this
    values = {
      arn = "arn:aws:imagebuilder:us-west-2:123456789012:image-pipeline/test-image"
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

  override_resource {
    target = aws_cloudwatch_event_connection.notify
    values = {
      arn = "arn:aws:events:us-west-2:123456789012:connection/test-image-notify/0123"
    }
  }

  override_resource {
    target = aws_cloudwatch_event_api_destination.notify
    values = {
      arn = "arn:aws:events:us-west-2:123456789012:api-destination/test-image-notify/0123"
    }
  }

  override_resource {
    target = aws_iam_role.notify
    values = {
      arn = "arn:aws:iam::123456789012:role/test-image-notify"
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
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }

  override_data {
    target = data.aws_ami.parent
    values = {
      id                    = "ami-0aaaaaaaaaaaaaaaa"
      block_device_mappings = []
    }
  }

  override_data {
    target = data.aws_ami.parent_snapshot
    values = {
      id                    = "ami-0123456789abcdef0"
      block_device_mappings = []
    }
  }

  override_data {
    target = data.aws_ebs_encryption_by_default.current
    values = {
      enabled = false
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
# Defaults — a private image in the build region only, built on demand
################################################################################

run "defaults" {
  command = plan


  assert {
    condition     = aws_imagebuilder_image_recipe.this.parent_image == "ami-0123456789abcdef0"
    error_message = "The recipe must build on parent_image"
  }

  # Pinned: a name that moves without its content moving would replace every
  # consumer's recipe and component on upgrade.
  assert {
    condition     = aws_imagebuilder_image_recipe.this.name == "test-image-4fd9befb"
    error_message = "The recipe must be named by a stable content hash, got ${aws_imagebuilder_image_recipe.this.name}"
  }

  assert {
    condition     = aws_imagebuilder_component.this["provision"].name == "test-image-provision-26a95f58"
    error_message = "An inline component must be named by a stable content hash, got ${aws_imagebuilder_component.this["provision"].name}"
  }

  assert {
    condition     = one(aws_imagebuilder_image_recipe.this.component[0].parameter).value == "v1.2.3"
    error_message = "Component parameters must be passed by the recipe"
  }

  assert {
    condition     = length(aws_imagebuilder_distribution_configuration.this.distribution) == 1
    error_message = "With no distribution_regions the image is produced in the build region only"
  }

  assert {
    condition     = length(one(one(aws_imagebuilder_distribution_configuration.this.distribution).ami_distribution_configuration).launch_permission) == 0
    error_message = "An image must be private by default"
  }

  assert {
    condition     = length(aws_ec2_image_block_public_access.this) == 0
    error_message = "The public-sharing block must be left alone for a private image"
  }

  assert {
    condition     = length(aws_imagebuilder_image_pipeline.this.schedule) == 0
    error_message = "The pipeline must be manual by default"
  }

  assert {
    condition     = length(aws_imagebuilder_image.this) == 0
    error_message = "No image must be built during apply by default"
  }

  assert {
    condition     = one(aws_imagebuilder_infrastructure_configuration.this.instance_metadata_options).http_tokens == "required"
    error_message = "The build instance must require IMDSv2"
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.instance) == 2
    error_message = "The instance role must carry exactly the two Image Builder policies by default"
  }
}

################################################################################
# Public, multi-region
################################################################################

run "public_multi_region" {
  command = plan

  variables {
    public               = true
    distribution_regions = ["us-east-1", "eu-west-1"]
    ami_tags             = { release = "v1.2.3" }
    root_volume = {
      device_name = "/dev/xvda"
      size_gb     = 30
    }
  }

  assert {
    condition     = length(aws_imagebuilder_distribution_configuration.this.distribution) == 3
    error_message = "The image must be distributed to the build region and every distribution region"
  }

  assert {
    condition = alltrue([
      for d in aws_imagebuilder_distribution_configuration.this.distribution :
      contains(one(one(d.ami_distribution_configuration).launch_permission).user_groups, "all")
    ])
    error_message = "Every region's image must be public"
  }

  assert {
    condition = alltrue([
      for d in aws_imagebuilder_distribution_configuration.this.distribution :
      one(d.ami_distribution_configuration).ami_tags["release"] == "v1.2.3"
    ])
    error_message = "Every region's image must carry ami_tags"
  }

  assert {
    condition     = toset(keys(aws_ec2_image_block_public_access.this)) == toset(["us-west-2", "us-east-1", "eu-west-1"])
    error_message = "Public sharing must be unblocked in every region an image lands in"
  }

  assert {
    condition     = one(one(aws_imagebuilder_image_recipe.this.block_device_mapping).ebs).encrypted == "false"
    error_message = "A public image's snapshot must not be encrypted"
  }
}

run "public_without_managing_the_block" {
  command = plan

  variables {
    public                           = true
    manage_image_block_public_access = false
  }

  assert {
    condition     = length(aws_ec2_image_block_public_access.this) == 0
    error_message = "The account setting must be left alone when it is managed elsewhere"
  }
}

run "public_refuses_an_encrypted_snapshot" {
  command = plan

  variables {
    public = true
    root_volume = {
      device_name = "/dev/xvda"
      size_gb     = 30
      encrypted   = true
    }
  }

  expect_failures = [aws_imagebuilder_image_recipe.this]
}

################################################################################
# Private volume defaults to encrypted
################################################################################

run "private_root_volume_is_encrypted" {
  command = plan

  variables {
    root_volume = {
      device_name = "/dev/xvda"
      size_gb     = 30
    }
  }

  assert {
    condition     = one(one(aws_imagebuilder_image_recipe.this.block_device_mapping).ebs).encrypted == "true"
    error_message = "A private image's snapshot must be encrypted by default"
  }
}

################################################################################
# Parent image lookup
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
    condition     = aws_imagebuilder_image_recipe.this.parent_image == "ami-0aaaaaaaaaaaaaaaa"
    error_message = "The recipe must build on the image the lookup found"
  }
}

run "parent_image_is_required" {
  command = plan

  variables {
    parent_image = null
  }

  expect_failures = [aws_imagebuilder_image_recipe.this]
}

################################################################################
# Immutable resources are renamed, not updated
################################################################################

run "changed_document_is_a_new_component_and_recipe" {
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

  assert {
    condition     = aws_imagebuilder_image_recipe.this.name != "test-image-4fd9befb"
    error_message = "A changed component must produce a differently named recipe"
  }
}

run "changed_parameter_is_a_new_recipe_over_the_same_component" {
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
    error_message = "A changed parameter must not produce a new component"
  }

  assert {
    condition     = aws_imagebuilder_image_recipe.this.name != "test-image-4fd9befb"
    error_message = "A changed parameter must produce a new recipe"
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
            commands   = ["test -x /usr/local/bin/runner"]
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
    error_message = "A parameter's value belongs to the recipe, not the document"
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
    condition     = length(aws_imagebuilder_image_recipe.this.component[0].parameter) == 0
    error_message = "A parameter left without a value must not be passed by the recipe"
  }

  # Pinned so the next run can prove a value leaves this component alone.
  assert {
    condition     = aws_imagebuilder_component.this["provision"].name == "test-image-provision-89e1f3f7"
    error_message = "A steps component must be named by a stable content hash, got ${aws_imagebuilder_component.this["provision"].name}"
  }
}

run "a_parameter_value_reaches_the_recipe_over_the_same_component" {
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
    condition     = one(aws_imagebuilder_image_recipe.this.component[0].parameter).value == "v1.2.3"
    error_message = "A parameter value must be passed by the recipe"
  }

  assert {
    condition     = aws_imagebuilder_component.this["provision"].name == "test-image-provision-89e1f3f7"
    error_message = "A parameter value must not change the component the recipe points at"
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
            inputs_json = jsonencode([{ source = "s3://releases/runner", destination = "/tmp/runner" }])
          },
          {
            name            = "Install"
            commands        = ["install -m 0755 /tmp/runner /usr/local/bin/runner"]
            timeout_seconds = 600
            max_attempts    = 2
          },
        ]
      },
    ]
  }

  assert {
    condition     = yamldecode(aws_imagebuilder_component.this["provision"].data).phases[0].steps[0].inputs[0].source == "s3://releases/runner"
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
}

run "a_changed_step_is_a_new_component" {
  command = plan

  variables {
    components = [
      {
        name        = "provision"
        source      = "steps"
        build_steps = [{ name = "Install", commands = ["echo installing something else"] }]
      },
    ]
  }

  assert {
    condition     = aws_imagebuilder_component.this["provision"].name != "test-image-provision-26a95f58"
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
# Referenced components, schedule, logs, build on apply
################################################################################

run "referenced_component_and_options" {
  command = plan

  variables {
    components = [
      {
        name = "update"
        arn  = "arn:aws:imagebuilder:us-west-2:aws:component/update-linux/x.x.x"
      },
    ]
    schedule_expression  = "cron(0 0 * * ? *)"
    log_bucket           = "example-logs"
    instance_policy_json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    build_on_apply       = true
    subnet_id            = "subnet-0123456789abcdef0"
    security_group_ids   = ["sg-0123456789abcdef0"]
  }

  assert {
    condition     = length(aws_imagebuilder_component.this) == 0
    error_message = "A referenced component must not be created"
  }

  assert {
    condition     = aws_imagebuilder_image_recipe.this.component[0].component_arn == "arn:aws:imagebuilder:us-west-2:aws:component/update-linux/x.x.x"
    error_message = "A referenced component must be used by ARN"
  }

  assert {
    condition     = one(aws_imagebuilder_image_pipeline.this.schedule).schedule_expression == "cron(0 0 * * ? *)"
    error_message = "The schedule must be set on the pipeline"
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
    condition     = length(aws_imagebuilder_image.this) == 1
    error_message = "build_on_apply must build an image"
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
}

run "subnet_requires_security_groups" {
  command = plan

  variables {
    subnet_id = "subnet-0123456789abcdef0"
  }

  expect_failures = [aws_imagebuilder_infrastructure_configuration.this]
}

run "component_needs_exactly_one_source" {
  command = plan

  variables {
    components = [{ name = "both", data = "x", arn = "arn:aws:imagebuilder:us-west-2:aws:component/x/1.0.0" }]
  }

  expect_failures = [var.components]
}

run "ami_name_must_be_unique_per_build" {
  command = plan

  variables {
    ami_name = "fixed-name"
  }

  expect_failures = [var.ami_name]
}

################################################################################
# Immutable resources are renamed, not updated
################################################################################

run "changed_description_is_a_new_recipe" {
  command = plan

  variables {
    description = "Bakes the sandbox guest image."
  }

  assert {
    condition     = aws_imagebuilder_image_recipe.this.name != "test-image-4fd9befb"
    error_message = "A changed description must produce a differently named recipe, got ${aws_imagebuilder_image_recipe.this.name}"
  }

  assert {
    condition     = aws_imagebuilder_component.this["provision"].name == "test-image-provision-26a95f58"
    error_message = "A changed recipe description must not produce a new component"
  }
}

################################################################################
# Build instance role name
################################################################################

run "a_long_name_still_fits_an_iam_role_name" {
  command = plan

  variables {
    name = "sandbox-guest-image-pipeline-for-the-us-west-2-build-fleet-2026"
  }

  assert {
    condition     = length(aws_iam_role.instance.name) == 64
    error_message = "A name too long for the suffix must be truncated to the IAM limit, got ${aws_iam_role.instance.name}"
  }

  assert {
    condition     = startswith(aws_iam_role.instance.name, "sandbox-guest-image-pipeline-for-the-us-west-2-build-fl")
    error_message = "A truncated role name must keep the head of the pipeline name, got ${aws_iam_role.instance.name}"
  }

  assert {
    condition     = aws_iam_instance_profile.instance.name == aws_iam_role.instance.name
    error_message = "The instance profile must carry the same name as the role"
  }
}

run "a_short_name_keeps_the_readable_role_name" {
  command = plan

  assert {
    condition     = aws_iam_role.instance.name == "test-image-image-builder"
    error_message = "A name that fits must be used as it is, got ${aws_iam_role.instance.name}"
  }
}

################################################################################
# Public images must be provably unencrypted before the build
################################################################################

run "public_refuses_an_encrypted_parent_image" {
  command = plan

  variables {
    public = true
  }

  override_data {
    target = data.aws_ami.parent_snapshot
    values = {
      id = "ami-0123456789abcdef0"
      block_device_mappings = [{
        device_name  = "/dev/xvda"
        ebs          = { encrypted = "true" }
        no_device    = ""
        virtual_name = ""
      }]
    }
  }

  expect_failures = [aws_imagebuilder_image_recipe.this]
}

run "public_refuses_a_parent_image_it_cannot_describe" {
  command = plan

  variables {
    public       = true
    parent_image = "ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
  }

  expect_failures = [aws_imagebuilder_image_recipe.this]
}

run "public_refuses_a_region_that_encrypts_by_default" {
  command = plan

  variables {
    public = true
  }

  override_data {
    target = data.aws_ebs_encryption_by_default.current
    values = {
      enabled = true
    }
  }

  expect_failures = [aws_imagebuilder_image_recipe.this]
}

run "a_private_image_ignores_encryption_by_default" {
  command = plan

  assert {
    condition     = length(data.aws_ebs_encryption_by_default.current) == 0
    error_message = "The account setting must be left unread for a private image"
  }

  assert {
    condition     = length(data.aws_ami.parent_snapshot) == 0
    error_message = "The parent image must be left undescribed for a private image"
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

################################################################################
# Starting a build from outside Terraform
################################################################################

run "no_pipeline_execution_policy_by_default" {
  command = plan

  assert {
    condition     = length(aws_iam_policy.pipeline_execution) == 0
    error_message = "The pipeline execution policy must be created only when it is asked for"
  }
}

run "pipeline_execution_policy" {
  command = plan

  variables {
    create_pipeline_execution_policy = true
  }

  assert {
    condition     = one(aws_iam_policy.pipeline_execution).name == "test-image-start-image-pipeline"
    error_message = "The policy must be named after the pipeline, got ${one(aws_iam_policy.pipeline_execution).name}"
  }

  assert {
    condition     = jsondecode(one(aws_iam_policy.pipeline_execution).policy).Statement[0].Resource == "arn:aws:imagebuilder:us-west-2:123456789012:image-pipeline/test-image"
    error_message = "The policy must reach this pipeline only"
  }

  assert {
    condition = toset(jsondecode(one(aws_iam_policy.pipeline_execution).policy).Statement[0].Action) == toset([
      "imagebuilder:StartImagePipelineExecution",
      "imagebuilder:GetImagePipeline",
      "imagebuilder:ListImagePipelineImages",
    ])
    error_message = "The policy must start the pipeline and read its runs, and nothing more"
  }

  assert {
    condition     = jsondecode(one(aws_iam_policy.pipeline_execution).policy).Statement[1].Resource == "arn:aws:imagebuilder:us-west-2:123456789012:image/test-image-*/*"
    error_message = "The policy must reach the images this pipeline produces, got ${jsondecode(one(aws_iam_policy.pipeline_execution).policy).Statement[1].Resource}"
  }
}

################################################################################
# Build on apply waits out the tests it contains
################################################################################

run "the_build_wait_outlasts_the_test_phase" {
  command = plan

  variables {
    build_on_apply              = true
    image_tests_timeout_minutes = 600
  }

  assert {
    condition     = one(aws_imagebuilder_image.this).timeouts.create == "660m"
    error_message = "A raised test timeout must raise the wait that contains it, got ${one(aws_imagebuilder_image.this).timeouts.create}"
  }
}

run "the_build_wait_keeps_its_original_length" {
  command = plan

  variables {
    build_on_apply = true
  }

  assert {
    condition     = one(aws_imagebuilder_image.this).timeouts.create == "120m"
    error_message = "The default wait must stay at two hours, got ${one(aws_imagebuilder_image.this).timeouts.create}"
  }
}

run "the_build_wait_must_contain_the_test_phase" {
  command = plan

  variables {
    build_on_apply        = true
    build_timeout_minutes = 30
  }

  expect_failures = [var.build_timeout_minutes]
}

################################################################################
# Build notification
################################################################################

# Notifications are off unless somewhere to send them AND something to prove
# they came from this account are both given. Half a configuration is not a
# quieter notification, it is an unauthenticated one.
run "no_notification_without_a_url" {
  command = plan

  variables {
    notify_header_value = "shhh"
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.notify) == 0
    error_message = "A secret with no endpoint must not create a rule"
  }
}

run "no_notification_without_a_secret" {
  command = plan

  variables {
    notify_url = "https://api.example.com/hooks/image-built"
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.notify) == 0
    error_message = "An endpoint with no secret must not create a rule"
  }
}

# The rule matches this pipeline's finished images and nothing else: a build
# still running produced no image, and another pipeline's images are somebody
# else's business.
run "the_rule_matches_only_this_pipelines_finished_images" {
  command = plan

  variables {
    notify_url          = "https://api.example.com/hooks/image-built"
    notify_header_value = "shhh"
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.notify) == 1
    error_message = "An endpoint and a secret must create a rule"
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.notify[0].event_pattern).source == ["aws.imagebuilder"]
    error_message = "The rule must listen to Image Builder"
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.notify[0].event_pattern).detail.state.status == ["AVAILABLE"]
    error_message = "The rule must only forward images that finished"
  }

  # Naming the recipe in full, separator and all, is what keeps a rule for
  # "test-image" from also forwarding "test-image-prod" images.
  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.notify[0].event_pattern).resources[0].prefix == "arn:aws:imagebuilder:us-west-2:123456789012:image/${lower(aws_imagebuilder_image_recipe.this.name)}/"
    error_message = "The rule must be confined to this recipe's images, got ${jsondecode(aws_cloudwatch_event_rule.notify[0].event_pattern).resources[0].prefix}"
  }

  assert {
    condition     = !startswith("arn:aws:imagebuilder:us-west-2:123456789012:image/test-image-prod-4fd9befb/1.0.0/1", jsondecode(aws_cloudwatch_event_rule.notify[0].event_pattern).resources[0].prefix)
    error_message = "The rule must not match a pipeline whose name starts with this one"
  }
}

# EventBridge caps a name at 64 characters and the pipeline name may use all 64
# on its own, so every notification name is bounded before it reaches AWS.
run "notification_names_stay_within_the_eventbridge_limit" {
  command = plan

  variables {
    name                = "an-image-pipeline-whose-name-uses-every-one-of-its-64-characters"
    notify_url          = "https://api.example.com/hooks/image-built"
    notify_header_value = "shhh"
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.notify[0].name) <= 64
    error_message = "The rule name must fit, got ${aws_cloudwatch_event_rule.notify[0].name}"
  }

  assert {
    condition     = length(aws_cloudwatch_event_connection.notify[0].name) <= 64
    error_message = "The connection name must fit, got ${aws_cloudwatch_event_connection.notify[0].name}"
  }

  assert {
    condition     = length(aws_cloudwatch_event_api_destination.notify[0].name) <= 64
    error_message = "The destination name must fit, got ${aws_cloudwatch_event_api_destination.notify[0].name}"
  }

  assert {
    condition     = length(aws_iam_role.notify[0].name) <= 64
    error_message = "The delivery role name must fit, got ${aws_iam_role.notify[0].name}"
  }

  assert {
    condition     = aws_cloudwatch_event_rule.notify[0].name != aws_cloudwatch_event_connection.notify[0].name
    error_message = "A truncated name must still tell the rule and the connection apart"
  }
}

# The delivery role can invoke this one destination and nothing else.
run "the_delivery_role_reaches_one_destination" {
  command = plan

  variables {
    notify_url          = "https://api.example.com/hooks/image-built"
    notify_header_value = "shhh"
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.notify[0].policy).Statement[0].Action == "events:InvokeApiDestination"
    error_message = "The role must only invoke a destination"
  }

  assert {
    condition     = jsondecode(aws_iam_role.notify[0].assume_role_policy).Statement[0].Principal.Service == "events.amazonaws.com"
    error_message = "Only EventBridge may assume the delivery role"
  }
}
