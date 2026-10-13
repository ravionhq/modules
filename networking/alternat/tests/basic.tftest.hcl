# alterNAT Module Tests
# Run with: tofu test
#
# The VPC is mocked as two availability zones with one public subnet each and
# private subnets whose route tables vary per test.

mock_provider "aws" {
  override_data {
    target = data.aws_vpc.this
    values = {
      owner_id = "123456789012"
      cidr_block_associations = [
        { association_id = "vpc-cidr-assoc-1", cidr_block = "10.0.0.0/16", state = "associated" },
      ]
      ipv6_cidr_block_associations = []
    }
  }

  # Instances of a for_each data source cannot be mocked individually, so
  # every subnet is mocked into one AZ with one private route table. Placement
  # across AZs and route tables is covered by placement.tftest.hcl.
  override_data {
    target = data.aws_subnet.public
    values = { vpc_id = "vpc-0123456789abcdef0", availability_zone = "us-west-2a" }
  }

  override_data {
    target = data.aws_subnet.private
    values = { vpc_id = "vpc-0123456789abcdef0", availability_zone = "us-west-2a" }
  }

  override_data {
    target = data.aws_route_tables.private_subnet
    values = { ids = ["rtb-private"] }
  }

  override_data {
    target = data.aws_route_tables.public_subnet
    values = { ids = ["rtb-public"] }
  }

  override_data {
    target = data.aws_nat_gateway.fallback
    values = { connectivity_type = "public" }
  }

  override_data {
    target = data.aws_nat_gateways.standby
    values = { ids = ["nat-0standby00000000a"] }
  }

  override_data {
    target = data.aws_route_table.main
    values = { id = "rtb-main" }
  }

  override_data {
    target = data.aws_ec2_instance_type.nat
    values = { supported_architectures = ["arm64"] }
  }

  override_data {
    target = data.aws_nat_gateways.existing
    values = { ids = ["nat-0123456789abcdef0"] }
  }

  override_data {
    target = data.aws_nat_gateway.existing
    values = { subnet_id = "subnet-public-b", connectivity_type = "public" }
  }
}

# alterNAT itself is tested upstream; these tests cover the wrapper around it.
override_module {
  target = module.alternat
  outputs = {
    nat_instance_eips              = ["198.51.100.10"]
    nat_gateway_eips               = []
    nat_instance_security_group_id = "sg-0123456789abcdef0"
    autoscaling_group_names        = ["test-nat-20261013000000000000000001"]
  }
}

variables {
  region             = "us-west-2"
  name               = "test"
  vpc_id             = "vpc-0123456789abcdef0"
  public_subnet_ids  = ["subnet-public-a", "subnet-public-b"]
  private_subnet_ids = ["subnet-private-a", "subnet-private-b"]
}

run "defaults" {
  command = plan

  assert {
    condition = local.vpc_az_maps == [
      { az = "us-west-2a", public_subnet_id = "subnet-public-a", route_table_ids = ["rtb-private"], private_subnet_ids = ["subnet-private-a", "subnet-private-b"] },
    ]
    error_message = "Expected one NAT instance serving the private route table."
  }

  assert {
    condition     = local.architecture == "arm64"
    error_message = "Expected the architecture to follow the Graviton instance type."
  }

  assert {
    condition     = local.fallback_nat_gateway_id == "nat-0123456789abcdef0"
    error_message = "Expected the VPC's only NAT gateway to be the fallback."
  }

  assert {
    condition     = length(aws_vpc_endpoint.ec2) == 1 && length(aws_vpc_endpoint.s3) == 0 && length(aws_vpc_endpoint.dynamodb) == 0
    error_message = "Expected only the EC2 interface endpoint by default."
  }

  assert {
    condition     = output.connectivity_tester_function_names == ["test-connectivity-tester-us-west-2a"]
    error_message = "Expected connectivity tester names derived from the module name."
  }
}

run "x86_instance_type" {
  command = plan

  variables {
    nat_instance_type = "c6in.large"
  }

  override_data {
    target = data.aws_ec2_instance_type.nat
    values = { supported_architectures = ["x86_64"] }
  }

  assert {
    condition     = local.architecture == "x86_64"
    error_message = "Expected the architecture to follow the x86 instance type."
  }
}

run "implicit_main_route_table" {
  command = plan

  override_data {
    target = data.aws_route_tables.private_subnet
    values = { ids = [] }
  }

  assert {
    condition     = local.route_table_ids == tolist(["rtb-main"])
    error_message = "Expected private subnets without an explicit association to use the main route table."
  }
}

run "gateway_endpoints" {
  command = plan

  variables {
    s3_gateway_endpoint_enabled       = true
    dynamodb_gateway_endpoint_enabled = true
  }

  assert {
    condition     = toset(aws_vpc_endpoint.s3[0].route_table_ids) == toset(["rtb-private"])
    error_message = "Expected the S3 gateway endpoint on the managed route tables."
  }

  assert {
    condition     = toset(aws_vpc_endpoint.dynamodb[0].route_table_ids) == toset(["rtb-private"])
    error_message = "Expected the DynamoDB gateway endpoint on the managed route tables."
  }
}

run "no_ec2_endpoint" {
  command = plan

  variables {
    ec2_endpoint_enabled = false
  }

  assert {
    condition     = length(aws_vpc_endpoint.ec2) == 0 && length(aws_security_group.ec2_endpoint) == 0
    error_message = "Expected no EC2 interface endpoint."
  }
}

run "create_fallback_nat_gateways" {
  command = plan

  variables {
    fallback_nat_gateway_mode = "create"
  }

  assert {
    condition     = local.fallback_nat_gateway_id == "" && length(local.existing_nat_gateway_ids) == 0
    error_message = "Expected create mode to ignore existing NAT gateways."
  }
}

run "create_mode_outputs_standby_nat_gateways" {
  command = apply

  variables {
    fallback_nat_gateway_mode = "create"
  }

  assert {
    condition     = output.fallback_nat_gateway_ids == tolist(["nat-0standby00000000a"])
    error_message = "Expected the standby NAT gateways as fallback gateways in create mode, for the fallback traffic charts."
  }
}

run "explicit_fallback_nat_gateway" {
  command = plan

  variables {
    fallback_nat_gateway_id = "nat-0fedcba9876543210"
  }

  assert {
    condition     = local.fallback_nat_gateway_id == "nat-0fedcba9876543210"
    error_message = "Expected the explicit fallback NAT gateway to win."
  }
}

run "several_nat_gateways_one_per_public_subnet" {
  command = plan

  override_data {
    target = data.aws_nat_gateways.existing
    values = { ids = ["nat-0000000000000000a", "nat-0000000000000000b"] }
  }

  override_data {
    target = data.aws_nat_gateway.existing
    values = { subnet_id = "subnet-public-a", connectivity_type = "public" }
  }

  assert {
    condition     = local.fallback_nat_gateway_id == ""
    error_message = "Expected each NAT instance to fail over to the NAT gateway in its own public subnet."
  }
}

run "several_nat_gateways_none_in_nat_subnet" {
  command = plan

  override_data {
    target = data.aws_nat_gateways.existing
    values = { ids = ["nat-0000000000000000a", "nat-0000000000000000b"] }
  }

  expect_failures = [terraform_data.preconditions]
}

run "no_existing_nat_gateway" {
  command = plan

  override_data {
    target = data.aws_nat_gateways.existing
    values = { ids = [] }
  }

  expect_failures = [terraform_data.preconditions]
}

run "nat_instance_eips" {
  command = plan

  variables {
    nat_instance_eip_allocation_ids = ["eipalloc-0123456789abcdef0"]
  }

  override_data {
    target = data.aws_eip.nat_instance
    values = { public_ip = "203.0.113.10" }
  }

  assert {
    condition     = output.nat_instance_public_ips == ["203.0.113.10"]
    error_message = "Expected the pre-allocated Elastic IPs to be the NAT instances' public IPs."
  }
}

run "nat_instance_eip_count_must_match" {
  command = plan

  variables {
    nat_instance_eip_allocation_ids = ["eipalloc-0123456789abcdef0", "eipalloc-0123456789abcdef1"]
  }

  override_data {
    target = data.aws_eip.nat_instance
    values = { public_ip = "203.0.113.10" }
  }

  expect_failures = [terraform_data.preconditions]
}

run "subnets_must_be_in_vpc" {
  command = plan

  override_data {
    target = data.aws_subnet.public
    values = { vpc_id = "vpc-0fedcba9876543210", availability_zone = "us-west-2a" }
  }

  expect_failures = [terraform_data.preconditions]
}

run "nat_restore_requires_ssm" {
  command = plan

  variables {
    ssm_enabled = false
  }

  expect_failures = [terraform_data.preconditions]
}

run "invalid_name" {
  command = plan

  variables {
    name = "Not_Valid"
  }

  expect_failures = [var.name]
}

run "invalid_lifetime" {
  command = plan

  variables {
    max_instance_lifetime_days = 400
  }

  expect_failures = [var.max_instance_lifetime_days]
}

run "explicit_private_fallback_nat_gateway" {
  command = plan

  variables {
    fallback_nat_gateway_id = "nat-0fedcba9876543210"
  }

  override_data {
    target = data.aws_nat_gateway.fallback
    values = { connectivity_type = "private" }
  }

  expect_failures = [terraform_data.preconditions]
}

# A route table used by both public and private subnets carries the Internet
# Gateway route the NAT instances need; alterNAT must not take it over.
run "public_and_private_subnets_share_route_table" {
  command = plan

  override_data {
    target = data.aws_route_tables.public_subnet
    values = { ids = ["rtb-private"] }
  }

  expect_failures = [terraform_data.preconditions]
}

run "public_and_private_subnets_both_on_main_route_table" {
  command = plan

  override_data {
    target = data.aws_route_tables.public_subnet
    values = { ids = [] }
  }

  override_data {
    target = data.aws_route_tables.private_subnet
    values = { ids = [] }
  }

  expect_failures = [terraform_data.preconditions]
}

# The VPC's only available NAT gateway is private, so there is nothing to fail
# over to.
run "only_private_nat_gateway" {
  command = plan

  override_data {
    target = data.aws_nat_gateway.existing
    values = { subnet_id = "subnet-public-b", connectivity_type = "private" }
  }

  expect_failures = [terraform_data.preconditions]
}
