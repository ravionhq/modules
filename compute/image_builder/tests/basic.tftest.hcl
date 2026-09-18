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
