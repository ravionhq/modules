mock_provider "aws" {
  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }

  override_data {
    target = data.aws_region.current
    values = {
      id     = "us-east-1"
      region = "us-east-1"
    }
  }
}

variables {
  name                             = "my-service"
  vpc_zone_identifier              = ["subnet-12345678"]
  launch_template_creation_enabled = false
  launch_template_id               = "lt-12345678"
}

run "fixed_name_remains_the_default" {
  command = plan

  assert {
    condition     = aws_autoscaling_group.this.name == "my-service"
    error_message = "Existing callers must retain fixed Auto Scaling Group names."
  }
}

run "prefix_generates_a_unique_group_name" {
  command = plan

  variables {
    name_prefix = "my-service-"
  }

  assert {
    condition     = aws_autoscaling_group.this.name_prefix == "my-service-" && aws_autoscaling_group.this.name != "my-service"
    error_message = "Prefix mode must configure a generated group name instead of the fixed name."
  }
}
