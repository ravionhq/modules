# Seed a fixed-name group with a mock apply, then use the real AWS provider
# schema for the replacement plan. The mock provider does not implement the
# provider's ForceNew logic, so both runs cannot use it.
mock_provider "aws" {
  alias = "seed"

  override_data {
    target = module.group.data.aws_caller_identity.current
    values = { account_id = "123456789012" }
  }

  override_data {
    target = module.group.data.aws_region.current
    values = { id = "us-east-1", region = "us-east-1" }
  }
}

provider "aws" {
  alias                       = "plan"
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_region_validation      = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
}

variables {
  name                             = "my-service"
  vpc_zone_identifier              = ["subnet-12345678"]
  launch_template_creation_enabled = false
  launch_template_id               = "lt-12345678"
}

run "create_fixed_group" {
  module { source = "./tests/replacement_fixture" }
  providers = { aws = aws.seed }

  assert {
    condition     = output.group_name == "my-service"
    error_message = "The initial group must use the fixed name."
  }
}

run "replace_with_generated_group" {
  command = plan
  module { source = "./tests/replacement_fixture" }
  providers = { aws = aws.plan }

  plan_options { refresh = false }

  variables { name_prefix = "my-service-" }

  override_data {
    target = module.group.data.aws_caller_identity.current
    values = { account_id = "123456789012" }
  }

  override_data {
    target = module.group.data.aws_region.current
    values = { id = "us-east-1", region = "us-east-1" }
  }

  assert {
    condition     = var.name_prefix == "my-service-"
    error_message = "The replacement plan must use the generated-name prefix."
  }
}
