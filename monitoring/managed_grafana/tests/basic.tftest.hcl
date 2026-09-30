################################################################################
# Managed Grafana Module Tests
#
# Plan only: an apply would run the data source provisioning script against a
# real workspace.
################################################################################

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }
  mock_data "aws_region" {
    defaults = {
      region = "us-west-2"
    }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
  mock_data "aws_ssoadmin_instances" {
    defaults = {
      identity_store_ids = ["d-1234567890"]
    }
  }
  mock_data "aws_identitystore_users" {
    defaults = {
      users = [
        { user_name = "alice@example.com", user_id = "11111111-1111-1111-1111-111111111111", identity_store_id = "d-1234567890", display_name = "", locale = "", nickname = "", preferred_language = "", profile_url = "", timezone = "", title = "", user_status = "ENABLED", user_type = "", addresses = [], emails = [], external_ids = [], name = [], phone_numbers = [] },
        { user_name = "bob@example.com", user_id = "22222222-2222-2222-2222-222222222222", identity_store_id = "d-1234567890", display_name = "", locale = "", nickname = "", preferred_language = "", profile_url = "", timezone = "", title = "", user_status = "ENABLED", user_type = "", addresses = [], emails = [], external_ids = [], name = [], phone_numbers = [] },
      ]
    }
  }
  mock_data "aws_identitystore_groups" {
    defaults = {
      groups = [
        { display_name = "Platform", group_id = "33333333-3333-3333-3333-333333333333", identity_store_id = "d-1234567890", description = "", external_ids = [] },
      ]
    }
  }
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock-role"
    }
  }
}

variables {
  name             = "test-grafana"
  admin_user_names = ["alice@example.com"]
}

################################################################################
# Defaults
################################################################################

run "identity_center_workspace_with_xray_and_cloudwatch_by_default" {
  command = plan

  assert {
    condition     = aws_grafana_workspace.this.authentication_providers == tolist(["AWS_SSO"]) && aws_grafana_workspace.this.permission_type == "CUSTOMER_MANAGED"
    error_message = "The workspace should sign users in through IAM Identity Center and read AWS data with the module's role."
  }

  assert {
    condition     = aws_grafana_workspace.this.grafana_version == "12.4" && aws_grafana_workspace.this.account_access_type == "CURRENT_ACCOUNT"
    error_message = "The workspace should run Grafana 12.4 and read its own account."
  }

  assert {
    condition     = jsondecode(aws_grafana_workspace.this.configuration) == { plugins = { pluginAdminEnabled = true }, unifiedAlerting = { enabled = true } }
    error_message = "Plugin management should be on for the X-Ray plugin, and unified alerting on, by default."
  }

  assert {
    condition     = aws_grafana_role_association.this["ADMIN"].user_ids == toset(["11111111-1111-1111-1111-111111111111"]) && length(aws_grafana_role_association.this) == 1
    error_message = "Only the named admin should be associated, by their Identity Center user ID."
  }

  assert {
    condition     = length(aws_grafana_workspace_saml_configuration.this) == 0
    error_message = "No SAML configuration should exist for Identity Center sign-in."
  }

  assert {
    condition     = [for data_source in terraform_data.data_sources.input : data_source.uid] == ["aws-xray", "aws-cloudwatch"]
    error_message = "X-Ray and CloudWatch should be the default data sources."
  }

  assert {
    condition     = terraform_data.data_sources.input[1].jsonData.tracingDatasourceUid == "aws-xray" && terraform_data.data_sources.input[1].jsonData.defaultRegion == "us-west-2"
    error_message = "CloudWatch should link traces to the X-Ray data source and default to the workspace's region."
  }

  assert {
    condition     = length(aws_iam_role_policy.cloudwatch) == 1 && length(aws_iam_role_policy.xray) == 1 && length(aws_iam_role_policy.prometheus) == 0
    error_message = "The role should read CloudWatch and X-Ray and no Prometheus workspace."
  }

  assert {
    condition     = alltrue([for action in data.aws_iam_policy_document.cloudwatch[0].statement[0].actions : !can(regex(":(Put|Create|Delete|Update|Set)", action))])
    error_message = "The CloudWatch policy should grant reads only."
  }
}

################################################################################
# Access
################################################################################

run "roles_map_users_and_groups" {
  command = plan

  variables {
    admin_user_names   = ["alice@example.com"]
    editor_user_names  = ["bob@example.com"]
    viewer_group_names = ["Platform"]
  }

  assert {
    condition     = keys(aws_grafana_role_association.this) == ["ADMIN", "EDITOR", "VIEWER"]
    error_message = "Each role with members should get an association."
  }

  assert {
    condition     = aws_grafana_role_association.this["EDITOR"].user_ids == toset(["22222222-2222-2222-2222-222222222222"])
    error_message = "The editor should be associated by user ID."
  }

  assert {
    condition     = aws_grafana_role_association.this["VIEWER"].group_ids == toset(["33333333-3333-3333-3333-333333333333"])
    error_message = "The viewer group should be associated by group ID."
  }
}

run "rejects_unknown_identity_center_users" {
  command = plan

  variables {
    admin_user_names = ["mallory@example.com"]
  }

  expect_failures = [aws_grafana_workspace.this]
}

run "saml_sign_in" {
  command = plan

  variables {
    authentication          = "saml"
    admin_user_names        = []
    saml_idp_metadata_url   = "https://idp.example.com/metadata.xml"
    saml_admin_role_values  = ["grafana-admins"]
    saml_editor_role_values = ["grafana-editors"]
  }

  assert {
    condition     = aws_grafana_workspace.this.authentication_providers == tolist(["SAML"])
    error_message = "The workspace should sign users in through SAML."
  }

  assert {
    condition     = aws_grafana_workspace_saml_configuration.this[0].idp_metadata_url == "https://idp.example.com/metadata.xml" && aws_grafana_workspace_saml_configuration.this[0].admin_role_values == tolist(["grafana-admins"])
    error_message = "The SAML configuration should carry the metadata URL and role values."
  }

  assert {
    condition     = length(aws_grafana_role_association.this) == 0
    error_message = "No Identity Center role associations should exist for SAML sign-in."
  }
}

run "rejects_saml_without_metadata" {
  command = plan

  variables {
    authentication   = "saml"
    admin_user_names = []
  }

  expect_failures = [aws_grafana_workspace.this]
}

################################################################################
# Data sources
################################################################################

run "prometheus_data_source_reads_one_workspace" {
  command = plan

  variables {
    prometheus_query_url     = "https://aps-workspaces.us-east-1.amazonaws.com/workspaces/ws-1234abcd-12ab-34cd-56ef-1234567890ab/"
    prometheus_workspace_arn = "arn:aws:aps:us-east-1:123456789012:workspace/ws-1234abcd-12ab-34cd-56ef-1234567890ab"
  }

  assert {
    condition     = terraform_data.data_sources.input[2].url == "https://aps-workspaces.us-east-1.amazonaws.com/workspaces/ws-1234abcd-12ab-34cd-56ef-1234567890ab"
    error_message = "The Prometheus data source should query the workspace endpoint without a trailing slash."
  }

  assert {
    condition     = terraform_data.data_sources.input[2].jsonData.sigV4Auth == true && terraform_data.data_sources.input[2].jsonData.sigV4Region == "us-east-1"
    error_message = "The Prometheus data source should sign with SigV4 in the workspace's region."
  }

  assert {
    condition     = data.aws_iam_policy_document.prometheus[0].statement[0].resources == toset(["arn:aws:aps:us-east-1:123456789012:workspace/ws-1234abcd-12ab-34cd-56ef-1234567890ab"])
    error_message = "The role should read the one Prometheus workspace only."
  }
}

run "rejects_prometheus_url_without_arn" {
  command = plan

  variables {
    prometheus_query_url = "https://aps-workspaces.us-east-1.amazonaws.com/workspaces/ws-1234abcd-12ab-34cd-56ef-1234567890ab"
  }

  expect_failures = [aws_grafana_workspace.this]
}

run "default_log_groups_and_data_source_region" {
  command = plan

  variables {
    data_source_region                 = "eu-west-1"
    cloudwatch_default_log_group_names = ["/ecs/otel/otlp-logs"]
  }

  assert {
    condition     = terraform_data.data_sources.input[1].jsonData.logGroups == [{ name = "/ecs/otel/otlp-logs", arn = "arn:aws:logs:eu-west-1:123456789012:log-group:/ecs/otel/otlp-logs" }]
    error_message = "CloudWatch should select the default log groups by name and ARN."
  }

  assert {
    condition     = terraform_data.data_sources.input[0].jsonData.defaultRegion == "eu-west-1"
    error_message = "X-Ray should default to the configured data source region."
  }
}

run "disabled_data_sources_are_left_out" {
  command = plan

  variables {
    xray_enabled       = false
    cloudwatch_enabled = false
  }

  assert {
    condition     = length(terraform_data.data_sources.input) == 0
    error_message = "No data sources should be provisioned."
  }

  assert {
    condition     = length(aws_iam_role_policy.cloudwatch) == 0 && length(aws_iam_role_policy.xray) == 0
    error_message = "The role should read nothing."
  }

  assert {
    condition     = jsondecode(aws_grafana_workspace.this.configuration).plugins.pluginAdminEnabled == false && terraform_data.data_sources.triggers_replace.plugins == ""
    error_message = "Without X-Ray, no plugin should be installed and plugin management should stay off."
  }
}

################################################################################
# Validation
################################################################################

################################################################################
# VPC connection and Loki
################################################################################

run "no_vpc_connection_by_default" {
  command = plan

  assert {
    condition     = length(aws_grafana_workspace.this.vpc_configuration) == 0 && length(module.security_group) == 0
    error_message = "Without a VPC ID the workspace should connect to no VPC and create no security group."
  }
}

run "loki_through_the_vpc_connection" {
  command = plan

  variables {
    vpc_id                 = "vpc-0123456789abcdef0"
    vpc_subnet_ids         = ["subnet-0a", "subnet-0b", ""]
    vpc_security_group_ids = ["sg-0lokiclient", ""]
    loki_query_url         = "http://internal-loki-123.elb.us-west-2.amazonaws.com:3100/"
  }

  assert {
    condition     = aws_grafana_workspace.this.vpc_configuration[0].subnet_ids == toset(["subnet-0a", "subnet-0b"])
    error_message = "The VPC connection should use the given subnets, leaving out the blanks a form sends."
  }

  assert {
    condition     = contains(aws_grafana_workspace.this.vpc_configuration[0].security_group_ids, "sg-0lokiclient") && length(aws_grafana_workspace.this.vpc_configuration[0].security_group_ids) == 2
    error_message = "The VPC connection should carry the module's security group and the Loki client group."
  }

  assert {
    condition     = output.security_group_id == module.security_group[0].security_group_id
    error_message = "The module's own security group should be published for allowing the workspace into private data sources."
  }

  assert {
    condition     = terraform_data.data_sources.input[2].uid == "loki" && terraform_data.data_sources.input[2].type == "loki" && terraform_data.data_sources.input[2].url == "http://internal-loki-123.elb.us-west-2.amazonaws.com:3100"
    error_message = "Loki should be a data source on its query URL without a trailing slash."
  }
}

run "rejects_loki_without_a_vpc_connection" {
  command = plan

  variables {
    loki_query_url = "http://internal-loki-123.elb.us-west-2.amazonaws.com:3100"
  }

  expect_failures = [aws_grafana_workspace.this]
}

run "rejects_a_vpc_connection_in_one_subnet" {
  command = plan

  variables {
    vpc_id         = "vpc-0123456789abcdef0"
    vpc_subnet_ids = ["subnet-0a"]
  }

  expect_failures = [aws_grafana_workspace.this]
}

run "rejects_subnets_without_a_vpc" {
  command = plan

  variables {
    vpc_subnet_ids = ["subnet-0a", "subnet-0b"]
  }

  expect_failures = [aws_grafana_workspace.this]
}

run "rejects_more_than_four_extra_security_groups" {
  command = plan

  variables {
    vpc_id                 = "vpc-0123456789abcdef0"
    vpc_subnet_ids         = ["subnet-0a", "subnet-0b"]
    vpc_security_group_ids = ["sg-01", "sg-02", "sg-03", "sg-04", "sg-05"]
  }

  expect_failures = [aws_grafana_workspace.this]
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "grafana workspace"
  }

  expect_failures = [var.name]
}

run "rejects_unknown_authentication" {
  command = plan

  variables {
    authentication = "oauth"
  }

  expect_failures = [var.authentication]
}

run "rejects_invalid_grafana_version" {
  command = plan

  variables {
    grafana_version = "latest"
  }

  expect_failures = [var.grafana_version]
}
