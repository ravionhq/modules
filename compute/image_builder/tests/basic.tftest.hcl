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
    condition     = aws_imagebuilder_image_recipe.this.name == "test-image-a25739fe"
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
    condition     = aws_imagebuilder_image_recipe.this.name != "test-image-a25739fe"
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
    condition     = aws_imagebuilder_image_recipe.this.name != "test-image-a25739fe"
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
