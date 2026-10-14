# NAT instance placement tests
# Run with: tofu test
#
# Exercises modules/placement directly with plain inputs: how many NAT
# instances run, in which availability zones, and which route tables each one
# serves.

variables {
  public_subnets = [
    { id = "subnet-public-a", availability_zone = "us-west-2a" },
    { id = "subnet-public-b", availability_zone = "us-west-2b" },
  ]
  high_availability_enabled = true
}

# Per-AZ private route tables, as in a Flightcontrol-created VPC or an
# rvn-aws-network VPC with NAT gateway high availability.
run "one_nat_instance_per_az" {
  command = plan

  module {
    source = "./modules/placement"
  }

  variables {
    private_subnets = [
      { id = "subnet-private-a", availability_zone = "us-west-2a", route_table_id = "rtb-private-a" },
      { id = "subnet-private-b", availability_zone = "us-west-2b", route_table_id = "rtb-private-b" },
    ]
  }

  assert {
    condition = output.vpc_az_maps == [
      { az = "us-west-2a", public_subnet_id = "subnet-public-a", route_table_ids = ["rtb-private-a"], private_subnet_ids = ["subnet-private-a"] },
      { az = "us-west-2b", public_subnet_id = "subnet-public-b", route_table_ids = ["rtb-private-b"], private_subnet_ids = ["subnet-private-b"] },
    ]
    error_message = "Expected each NAT instance to serve only its own availability zone's route table."
  }

  assert {
    condition     = output.endpoint_subnet_ids == ["subnet-private-a", "subnet-private-b"]
    error_message = "Expected one endpoint subnet per availability zone."
  }
}

run "single_nat_instance" {
  command = plan

  module {
    source = "./modules/placement"
  }

  variables {
    high_availability_enabled = false
    private_subnets = [
      { id = "subnet-private-a", availability_zone = "us-west-2a", route_table_id = "rtb-private-a" },
      { id = "subnet-private-b", availability_zone = "us-west-2b", route_table_id = "rtb-private-b" },
    ]
  }

  assert {
    condition = output.vpc_az_maps == [
      { az = "us-west-2a", public_subnet_id = "subnet-public-a", route_table_ids = ["rtb-private-a", "rtb-private-b"], private_subnet_ids = ["subnet-private-a", "subnet-private-b"] },
    ]
    error_message = "Expected one NAT instance serving every private route table."
  }
}

# One private route table for every AZ, as in an rvn-aws-network VPC without
# NAT gateway high availability.
run "shared_private_route_table" {
  command = plan

  module {
    source = "./modules/placement"
  }

  variables {
    private_subnets = [
      { id = "subnet-private-a", availability_zone = "us-west-2a", route_table_id = "rtb-private" },
      { id = "subnet-private-b", availability_zone = "us-west-2b", route_table_id = "rtb-private" },
      { id = "subnet-private-c", availability_zone = "us-west-2c", route_table_id = "rtb-private" },
    ]
  }

  assert {
    condition = output.vpc_az_maps == [
      { az = "us-west-2a", public_subnet_id = "subnet-public-a", route_table_ids = ["rtb-private"], private_subnet_ids = ["subnet-private-a", "subnet-private-b", "subnet-private-c"] },
    ]
    error_message = "Expected a single NAT instance when the private subnets share one route table."
  }
}

# A private AZ without a public subnet is served from an AZ that has one.
run "private_az_without_public_subnet" {
  command = plan

  module {
    source = "./modules/placement"
  }

  variables {
    private_subnets = [
      { id = "subnet-private-a", availability_zone = "us-west-2a", route_table_id = "rtb-private-a" },
      { id = "subnet-private-b", availability_zone = "us-west-2b", route_table_id = "rtb-private-b" },
      { id = "subnet-private-c", availability_zone = "us-west-2c", route_table_id = "rtb-private-c" },
    ]
  }

  assert {
    condition     = output.nat_azs == tolist(["us-west-2a", "us-west-2b"])
    error_message = "Expected NAT instances only in availability zones with a public subnet."
  }

  assert {
    condition     = output.route_table_nat_az["rtb-private-c"] == "us-west-2a"
    error_message = "Expected the route table of the AZ without a public subnet to use the first NAT instance."
  }
}

# The first public subnet listed in an AZ hosts its NAT instance.
run "first_public_subnet_per_az" {
  command = plan

  module {
    source = "./modules/placement"
  }

  variables {
    public_subnets = [
      { id = "subnet-public-a2", availability_zone = "us-west-2a" },
      { id = "subnet-public-a1", availability_zone = "us-west-2a" },
    ]
    private_subnets = [
      { id = "subnet-private-a", availability_zone = "us-west-2a", route_table_id = "rtb-private-a" },
    ]
  }

  assert {
    condition     = output.vpc_az_maps[0].public_subnet_id == "subnet-public-a2"
    error_message = "Expected the first listed public subnet of the AZ."
  }
}

# Several private subnets in one AZ on one route table.
run "several_private_subnets_per_az" {
  command = plan

  module {
    source = "./modules/placement"
  }

  variables {
    private_subnets = [
      { id = "subnet-private-a1", availability_zone = "us-west-2a", route_table_id = "rtb-private-a" },
      { id = "subnet-private-a2", availability_zone = "us-west-2a", route_table_id = "rtb-private-a" },
      { id = "subnet-private-b1", availability_zone = "us-west-2b", route_table_id = "rtb-private-b" },
    ]
  }

  assert {
    condition     = output.vpc_az_maps[0].private_subnet_ids == ["subnet-private-a1", "subnet-private-a2"]
    error_message = "Expected the NAT instance's connectivity tester in every private subnet it serves."
  }

  assert {
    condition     = output.endpoint_subnet_ids == ["subnet-private-a1", "subnet-private-b1"]
    error_message = "Expected one endpoint subnet per availability zone."
  }
}
