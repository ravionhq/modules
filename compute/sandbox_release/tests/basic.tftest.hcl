# Sandbox release module tests — run from module root: tofu test

mock_provider "aws" {
  override_data {
    target = data.aws_ami.host
    values = {
      id = "ami-0123456789abcdef0"
    }
  }

  override_resource {
    target = aws_ssm_parameter.release
    values = {
      arn = "arn:aws:ssm:us-west-2:123456789012:parameter/ravion/sandbox-host/release"
    }
  }
}

variables {
  region          = "us-west-2"
  runner_version  = "v1.1.37"
  guest_image_key = "guest/ecdb0efe4b101732"
}

run "publishes_the_pair_the_pools_read" {
  command = plan

  assert {
    condition     = aws_ssm_parameter.release.value == jsonencode({ runnerVersion = "v1.1.37", guestImageKey = "guest/ecdb0efe4b101732" })
    error_message = "the published value is the pair a pool decodes"
  }

  assert {
    condition     = aws_ssm_parameter.release.name == "/ravion/sandbox-host/release"
    error_message = "the default parameter is where every pool looks"
  }

  assert {
    condition     = length(data.aws_ami.host) == 1
    error_message = "the image is checked before the release is published"
  }
}

run "publishing_without_the_check_looks_up_nothing" {
  command = plan

  variables {
    verify_image = false
  }

  assert {
    condition     = length(data.aws_ami.host) == 0
    error_message = "the check is what the flag turns off"
  }
}

run "refuses_a_runner_version_that_is_not_one" {
  command = plan

  variables {
    runner_version = "1.1.37"
  }

  expect_failures = [var.runner_version]
}

run "refuses_a_guest_key_that_is_not_one" {
  command = plan

  variables {
    guest_image_key = "guest/nothex"
  }

  expect_failures = [var.guest_image_key]
}
