# Fallback NAT gateway selection tests
# Run with: tofu test
#
# Exercises modules/fallback directly with plain inputs, including VPCs with
# both public and private NAT gateways, which the root tests cannot mock
# because each gateway is a for_each instance of one data source.

variables {
  nat_instances = [
    { availability_zone = "us-west-2a", public_subnet_id = "subnet-public-a" },
    { availability_zone = "us-west-2b", public_subnet_id = "subnet-public-b" },
  ]
}

# One public and one private gateway: the private one is dropped and the
# public one serves every alterNAT instance.
run "mixed_gateways_use_the_public_one" {
  command = plan

  module {
    source = "./modules/fallback"
  }

  variables {
    nat_gateways = [
      { id = "nat-private", subnet_id = "subnet-private-a", connectivity_type = "private" },
      { id = "nat-public", subnet_id = "subnet-public-b", connectivity_type = "public" },
    ]
  }

  assert {
    condition     = output.valid
    error_message = "Expected a usable fallback."
  }

  assert {
    condition     = output.public_nat_gateway_ids == tolist(["nat-public"])
    error_message = "Expected the private NAT gateway to be dropped."
  }

  assert {
    condition     = output.fallback_nat_gateway_id == "nat-public"
    error_message = "Expected the only public NAT gateway as every alterNAT instance's fallback."
  }

  assert {
    condition     = output.fallback_nat_gateway_ids == tolist(["nat-public"])
    error_message = "Expected only the public NAT gateway in the fallback list."
  }
}

# A private gateway in an alterNAT instance's own subnet is not a fallback,
# even though it would otherwise be picked by subnet.
run "mixed_gateways_per_subnet" {
  command = plan

  module {
    source = "./modules/fallback"
  }

  variables {
    nat_gateways = [
      { id = "nat-public-a", subnet_id = "subnet-public-a", connectivity_type = "public" },
      { id = "nat-public-b", subnet_id = "subnet-public-b", connectivity_type = "public" },
      { id = "nat-private-b", subnet_id = "subnet-public-b", connectivity_type = "private" },
    ]
  }

  assert {
    condition     = output.valid
    error_message = "Expected every alterNAT instance to have a public NAT gateway in its subnet."
  }

  assert {
    condition     = output.fallback_nat_gateway_id == ""
    error_message = "Expected per-subnet fallback with several public NAT gateways."
  }

  assert {
    condition     = output.fallback_nat_gateway_ids == tolist(["nat-public-a", "nat-public-b"])
    error_message = "Expected only the public NAT gateways in the fallback list."
  }
}

# The only gateway in us-west-2a's subnet is private, so that alterNAT
# instance has no fallback.
run "mixed_gateways_missing_public_in_one_subnet" {
  command = plan

  module {
    source = "./modules/fallback"
  }

  variables {
    nat_gateways = [
      { id = "nat-private-a", subnet_id = "subnet-public-a", connectivity_type = "private" },
      { id = "nat-public-b", subnet_id = "subnet-public-b", connectivity_type = "public" },
      { id = "nat-public-c", subnet_id = "subnet-public-c", connectivity_type = "public" },
    ]
  }

  assert {
    condition     = !output.valid
    error_message = "Expected no usable fallback for us-west-2a."
  }

  assert {
    condition     = strcontains(output.error_message, "us-west-2a") && !strcontains(output.error_message, "us-west-2b")
    error_message = "Expected the error to name only the AZ without a public NAT gateway."
  }
}

run "only_private_gateways" {
  command = plan

  module {
    source = "./modules/fallback"
  }

  variables {
    nat_gateways = [
      { id = "nat-private-a", subnet_id = "subnet-public-a", connectivity_type = "private" },
    ]
  }

  assert {
    condition     = !output.valid && length(output.fallback_nat_gateway_ids) == 0
    error_message = "Expected no fallback when every NAT gateway is private."
  }

  assert {
    condition     = strcontains(output.error_message, "no available public NAT gateway")
    error_message = "Expected the no-public-gateway error."
  }
}

# An explicit gateway wins, whatever else is in the VPC.
run "explicit_gateway" {
  command = plan

  module {
    source = "./modules/fallback"
  }

  variables {
    fallback_nat_gateway_id = "nat-explicit"
    nat_gateways = [
      { id = "nat-public-a", subnet_id = "subnet-public-a", connectivity_type = "public" },
      { id = "nat-private-b", subnet_id = "subnet-public-b", connectivity_type = "private" },
    ]
  }

  assert {
    condition     = output.valid && output.fallback_nat_gateway_id == "nat-explicit"
    error_message = "Expected the explicit NAT gateway."
  }

  assert {
    condition     = output.fallback_nat_gateway_ids == tolist(["nat-explicit"])
    error_message = "Expected only the explicit NAT gateway in the fallback list."
  }
}
