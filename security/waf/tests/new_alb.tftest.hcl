# Associating a load balancer created in the same plan — run from module root:
# tofu test. Its ARN is only known after apply, so the association must not
# key on it.

provider "aws" {
  region                      = "us-west-2"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  access_key                  = "test"
  secret_key                  = "test"
}

run "plans_with_an_alb_created_in_the_same_plan" {
  command = plan

  module {
    source = "./tests/fixtures/new_alb"
  }

  assert {
    condition     = length(module.waf.associated_alb_arns) == 1
    error_message = "The new ALB must be planned for association."
  }
}
