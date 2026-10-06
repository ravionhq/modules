# Basic VPC Module Tests
# Run with: tofu test

# Mock AWS provider with overridden data sources
mock_provider "aws" {
  override_data {
    target = data.aws_availability_zones.available
    values = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1e", "us-east-1f"]
    }
  }

  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }

  override_data {
    target = data.aws_region.current
    values = {
      id   = "us-east-1"
      name = "us-east-1"
    }
  }

  # Override resources that need valid ARNs
  override_resource {
    target = aws_cloudwatch_log_group.flow_logs
    values = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/vpc-flow-logs/test-vpc"
    }
  }

  override_resource {
    target = aws_iam_role.flow_logs
    values = {
      arn = "arn:aws:iam::123456789012:role/test-vpc-vpc-flow-logs"
    }
  }

  override_resource {
    target = aws_s3_bucket.flow_logs
    values = {
      arn = "arn:aws:s3:::test-vpc-vpc-flow-logs-123456789012-us-east-1"
    }
  }
}

variables {
  name = "test-vpc"
}

# Test 1: Basic VPC creation with defaults
run "basic_vpc" {
  command = plan

  assert {
    condition     = aws_vpc.this.cidr_block == "10.0.0.0/16"
    error_message = "VPC CIDR block should default to 10.0.0.0/16"
  }

  assert {
    condition     = aws_vpc.this.enable_dns_support == true
    error_message = "DNS support should be enabled by default"
  }

  assert {
    condition     = aws_vpc.this.enable_dns_hostnames == true
    error_message = "DNS hostnames should be enabled by default"
  }

  assert {
    condition     = length(aws_subnet.public) == 3
    error_message = "Should create 3 public subnets by default"
  }

  assert {
    condition     = length(aws_subnet.private) == 3
    error_message = "Should create 3 private subnets by default"
  }
}

# Test 1a: Default subnet count adapts to two-AZ regions/accounts
run "default_subnet_count_two_available_azs" {
  command = plan

  override_data {
    target = data.aws_availability_zones.available
    values = {
      names = ["us-west-1b", "us-west-1c"]
    }
  }

  override_data {
    target = data.aws_region.current
    values = {
      id   = "us-west-1"
      name = "us-west-1"
    }
  }

  assert {
    condition     = length(aws_subnet.public) == 2
    error_message = "Should create 2 public subnets by default when only 2 AZs are available"
  }

  assert {
    condition     = length(aws_subnet.private) == 2
    error_message = "Should create 2 private subnets by default when only 2 AZs are available"
  }

  assert {
    condition     = aws_subnet.public[0].availability_zone == "us-west-1b" && aws_subnet.public[1].availability_zone == "us-west-1c"
    error_message = "Should place default subnets in the available AZs"
  }
}

# Test 1b: Explicit subnet count still fails when it exceeds available AZs
run "explicit_subnet_count_exceeds_available_azs" {
  command = plan

  variables {
    subnet_count = 3
  }

  override_data {
    target = data.aws_availability_zones.available
    values = {
      names = ["us-west-1b", "us-west-1c"]
    }
  }

  expect_failures = [
    aws_vpc.this,
  ]
}

# Test 2: Custom VPC CIDR
run "custom_cidr" {
  command = plan

  variables {
    vpc_cidr = "172.16.0.0/16"
  }

  assert {
    condition     = aws_vpc.this.cidr_block == "172.16.0.0/16"
    error_message = "VPC CIDR block should be 172.16.0.0/16"
  }
}

# Test 3: Custom subnet count
run "custom_subnet_count" {
  command = plan

  variables {
    subnet_count = 2
  }

  assert {
    condition     = length(aws_subnet.public) == 2
    error_message = "Should create 2 public subnets"
  }

  assert {
    condition     = length(aws_subnet.private) == 2
    error_message = "Should create 2 private subnets"
  }
}

# Test 4: NAT Gateway enabled (single)
run "nat_gateway_single" {
  command = plan

  variables {
    nat_gateway_enabled                   = true
    nat_gateway_high_availability_enabled = false
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "Should create 1 NAT Gateway when nat_gateway_high_availability_enabled is false"
  }

  assert {
    condition     = length(aws_eip.nat) == 1
    error_message = "Should create 1 EIP for NAT Gateway"
  }
}

# Test 5: NAT Gateway enabled (HA - one per AZ)
run "nat_gateway_ha" {
  command = plan

  variables {
    nat_gateway_enabled                   = true
    nat_gateway_high_availability_enabled = true
    subnet_count                          = 3
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 3
    error_message = "Should create 3 NAT Gateways when nat_gateway_high_availability_enabled is true"
  }

  assert {
    condition     = length(aws_eip.nat) == 3
    error_message = "Should create 3 EIPs for NAT Gateways"
  }
}

# Test 5a: Empty EIP allocation list is treated as "allocate internally"
run "nat_gateway_empty_eip_list" {
  command = plan

  variables {
    nat_gateway_enabled                   = true
    nat_gateway_high_availability_enabled = false
    nat_gateway_eip_allocation_ids        = []
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "Should create 1 NAT Gateway with an empty EIP allocation list"
  }

  assert {
    condition     = length(aws_eip.nat) == 1
    error_message = "Empty nat_gateway_eip_allocation_ids should fall back to module-created EIPs"
  }
}

# Test 5a-ha: Empty EIP allocation list also auto-allocates in HA mode
run "nat_gateway_empty_eip_list_ha" {
  command = plan

  variables {
    nat_gateway_enabled                   = true
    nat_gateway_high_availability_enabled = true
    subnet_count                          = 3
    nat_gateway_eip_allocation_ids        = []
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 3
    error_message = "Should create 3 NAT Gateways in HA mode with an empty EIP allocation list"
  }

  assert {
    condition     = length(aws_eip.nat) == 3
    error_message = "Empty nat_gateway_eip_allocation_ids should fall back to 3 module-created EIPs in HA mode"
  }
}

# Test 5b: Supplied EIP allocation IDs are used instead of creating EIPs
run "nat_gateway_supplied_eips" {
  command = plan

  variables {
    nat_gateway_enabled                   = true
    nat_gateway_high_availability_enabled = false
    nat_gateway_eip_allocation_ids        = ["eipalloc-0123456789abcdef0"]
  }

  assert {
    condition     = length(aws_eip.nat) == 0
    error_message = "Should not create EIPs when allocation IDs are supplied"
  }

  assert {
    condition     = aws_nat_gateway.this[0].allocation_id == "eipalloc-0123456789abcdef0"
    error_message = "NAT Gateway should use the supplied EIP allocation ID"
  }
}

# Test 5c: Supplied EIP count must match NAT Gateway count
run "nat_gateway_supplied_eips_wrong_count" {
  command = plan

  variables {
    nat_gateway_enabled                   = true
    nat_gateway_high_availability_enabled = true
    subnet_count                          = 3
    nat_gateway_eip_allocation_ids        = ["eipalloc-0123456789abcdef0"]
  }

  expect_failures = [
    var.nat_gateway_eip_allocation_ids,
  ]
}

# Test 6: NAT Gateway disabled
run "nat_gateway_disabled" {
  command = plan

  variables {
    nat_gateway_enabled = false
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 0
    error_message = "Should not create NAT Gateway when disabled"
  }

  assert {
    condition     = length(aws_eip.nat) == 0
    error_message = "Should not create EIP when NAT Gateway disabled"
  }
}

# Test 7: IPv6 enabled
run "ipv6_enabled" {
  command = plan

  variables {
    ipv6_enabled = true
  }

  override_resource {
    target = aws_vpc.this
    values = {
      ipv6_cidr_block = "2600:1f18::/56"
    }
  }

  assert {
    condition     = aws_vpc.this.assign_generated_ipv6_cidr_block == true
    error_message = "VPC should have IPv6 CIDR block assigned"
  }

  assert {
    condition     = length(aws_egress_only_internet_gateway.this) == 1
    error_message = "Should create Egress-Only Internet Gateway for IPv6"
  }
}

# Test 8: IPv6 disabled
run "ipv6_disabled" {
  command = plan

  variables {
    ipv6_enabled = false
  }

  assert {
    condition     = aws_vpc.this.assign_generated_ipv6_cidr_block == false
    error_message = "VPC should not have IPv6 CIDR block assigned"
  }

  assert {
    condition     = length(aws_egress_only_internet_gateway.this) == 0
    error_message = "Should not create Egress-Only Internet Gateway"
  }
}

# Test 9: Flow Logs to CloudWatch - resource counts
run "flow_logs_cloudwatch" {
  command = plan

  variables {
    flow_logs_enabled        = true
    flow_logs_destination    = "cloudwatch"
    flow_logs_retention_days = 30
  }

  assert {
    condition     = length(aws_flow_log.cloudwatch) == 1
    error_message = "Should create CloudWatch Flow Log"
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.flow_logs) == 1
    error_message = "Should create CloudWatch Log Group"
  }

  assert {
    condition     = length(aws_iam_role.flow_logs) == 1
    error_message = "Should create IAM Role for Flow Logs"
  }

  assert {
    condition     = length(aws_flow_log.s3) == 0
    error_message = "Should not create S3 Flow Log"
  }
}

# Test 10: Flow Logs to S3 (new bucket)
run "flow_logs_s3_new_bucket" {
  command = plan

  variables {
    flow_logs_enabled     = true
    flow_logs_destination = "s3"
  }

  assert {
    condition     = length(aws_flow_log.s3) == 1
    error_message = "Should create S3 Flow Log"
  }

  assert {
    condition     = length(aws_s3_bucket.flow_logs) == 1
    error_message = "Should create S3 bucket for Flow Logs"
  }

  assert {
    condition     = length(aws_flow_log.cloudwatch) == 0
    error_message = "Should not create CloudWatch Flow Log"
  }
}

# Test 11: Flow Logs to S3 (existing bucket)
run "flow_logs_s3_existing_bucket" {
  command = plan

  variables {
    flow_logs_enabled       = true
    flow_logs_destination   = "s3"
    flow_logs_s3_bucket_arn = "arn:aws:s3:::my-existing-bucket"
  }

  assert {
    condition     = length(aws_flow_log.s3) == 1
    error_message = "Should create S3 Flow Log"
  }

  assert {
    condition     = length(aws_s3_bucket.flow_logs) == 0
    error_message = "Should not create S3 bucket when existing ARN provided"
  }
}

# Test 12: Flow Logs disabled
run "flow_logs_disabled" {
  command = plan

  variables {
    flow_logs_enabled = false
  }

  assert {
    condition     = length(aws_flow_log.cloudwatch) == 0
    error_message = "Should not create CloudWatch Flow Log"
  }

  assert {
    condition     = length(aws_flow_log.s3) == 0
    error_message = "Should not create S3 Flow Log"
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.flow_logs) == 0
    error_message = "Should not create CloudWatch Log Group"
  }

  assert {
    condition     = length(aws_s3_bucket.flow_logs) == 0
    error_message = "Should not create S3 bucket"
  }
}

# Test 13: Custom subnet CIDRs
run "custom_subnet_cidrs" {
  command = plan

  variables {
    subnet_count         = 2
    public_subnet_cidrs  = ["10.0.100.0/24", "10.0.101.0/24"]
    private_subnet_cidrs = ["10.0.200.0/24", "10.0.201.0/24"]
  }

  assert {
    condition     = aws_subnet.public[0].cidr_block == "10.0.100.0/24"
    error_message = "First public subnet should use custom CIDR"
  }

  assert {
    condition     = aws_subnet.private[0].cidr_block == "10.0.200.0/24"
    error_message = "First private subnet should use custom CIDR"
  }
}

# Test 14: Resource tagging
run "resource_tagging" {
  command = plan

  variables {
    tags = {
      Environment = "test"
      Project     = "myproject"
    }
  }

  assert {
    condition     = aws_vpc.this.tags["Environment"] == "test"
    error_message = "VPC should have Environment tag"
  }

  assert {
    condition     = aws_vpc.this.tags["ManagedBy"] == "terraform"
    error_message = "VPC should have default ManagedBy tag"
  }
}

# Test 15: Public subnets have correct settings
run "public_subnet_settings" {
  command = plan

  assert {
    condition     = aws_subnet.public[0].map_public_ip_on_launch == true
    error_message = "Public subnets should auto-assign public IPs"
  }

  assert {
    condition     = aws_subnet.public[0].tags["Tier"] == "public"
    error_message = "Public subnets should have Tier=public tag"
  }
}

# Test 16: Private subnets have correct settings
run "private_subnet_settings" {
  command = plan

  assert {
    condition     = aws_subnet.private[0].map_public_ip_on_launch == false
    error_message = "Private subnets should not auto-assign public IPs"
  }

  assert {
    condition     = aws_subnet.private[0].tags["Tier"] == "private"
    error_message = "Private subnets should have Tier=private tag"
  }
}

# Test 17: Route tables created correctly
run "route_tables" {
  command = plan

  variables {
    nat_gateway_high_availability_enabled = false
  }

  assert {
    condition     = length(aws_route_table.private) == 1
    error_message = "Should create 1 private route table when nat_gateway_high_availability_enabled is false"
  }
}

# Test 18: Multiple private route tables for HA NAT
run "route_tables_ha" {
  command = plan

  variables {
    nat_gateway_high_availability_enabled = true
    subnet_count                          = 3
  }

  assert {
    condition     = length(aws_route_table.private) == 3
    error_message = "Should create 3 private route tables when nat_gateway_high_availability_enabled is true"
  }
}

# Test 19: DNS settings can be disabled
run "dns_disabled" {
  command = plan

  variables {
    dns_support_enabled   = false
    dns_hostnames_enabled = false
  }

  assert {
    condition     = aws_vpc.this.enable_dns_support == false
    error_message = "DNS support should be disabled"
  }

  assert {
    condition     = aws_vpc.this.enable_dns_hostnames == false
    error_message = "DNS hostnames should be disabled"
  }
}

# Test 20: Internet Gateway is always created
run "internet_gateway" {
  command = plan

  assert {
    condition     = aws_internet_gateway.this.vpc_id == aws_vpc.this.id
    error_message = "Internet Gateway should be attached to VPC"
  }
}

# Test 21: Public route has internet gateway
run "public_route" {
  command = plan

  assert {
    condition     = aws_route.public_internet.destination_cidr_block == "0.0.0.0/0"
    error_message = "Public route should have 0.0.0.0/0 destination"
  }

  assert {
    condition     = aws_route.public_internet.gateway_id == aws_internet_gateway.this.id
    error_message = "Public route should use Internet Gateway"
  }
}

# Test 22: Subnet count of 1
run "single_subnet" {
  command = plan

  variables {
    subnet_count = 1
  }

  assert {
    condition     = length(aws_subnet.public) == 1
    error_message = "Should create 1 public subnet"
  }

  assert {
    condition     = length(aws_subnet.private) == 1
    error_message = "Should create 1 private subnet"
  }
}

# Test 23: Maximum subnet count of 6
run "max_subnets" {
  command = plan

  variables {
    subnet_count = 6
  }

  assert {
    condition     = length(aws_subnet.public) == 6
    error_message = "Should create 6 public subnets"
  }

  assert {
    condition     = length(aws_subnet.private) == 6
    error_message = "Should create 6 private subnets"
  }
}

# Test 24: CloudWatch log retention is set correctly
run "cloudwatch_retention" {
  command = plan

  variables {
    flow_logs_enabled        = true
    flow_logs_destination    = "cloudwatch"
    flow_logs_retention_days = 90
  }

  assert {
    condition     = aws_cloudwatch_log_group.flow_logs[0].retention_in_days == 90
    error_message = "CloudWatch log retention should be 90 days"
  }
}

# Test 25: S3 bucket security configurations
run "s3_security" {
  command = plan

  variables {
    flow_logs_enabled     = true
    flow_logs_destination = "s3"
  }

  assert {
    condition     = length(aws_s3_bucket_server_side_encryption_configuration.flow_logs) == 1
    error_message = "S3 bucket should have encryption configuration"
  }

  assert {
    condition     = length(aws_s3_bucket_public_access_block.flow_logs) == 1
    error_message = "S3 bucket should block public access"
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.flow_logs) == 1
    error_message = "S3 bucket should have lifecycle configuration"
  }
}

# Test 26: No VPC peering connections by default
run "vpc_peering_disabled" {
  command = plan

  assert {
    condition     = length(aws_vpc_peering_connection.this) == 0
    error_message = "Should not create any VPC peering connections by default"
  }

  assert {
    condition     = length(aws_route.public_vpc_peering) == 0
    error_message = "Should not create any public VPC peering routes by default"
  }

  assert {
    condition     = length(aws_route.private_vpc_peering) == 0
    error_message = "Should not create any private VPC peering routes by default"
  }
}

# Test 27: Single VPC peering, same account/region, single private route table
run "vpc_peering_single" {
  command = plan

  variables {
    nat_gateway_enabled                   = true
    nat_gateway_high_availability_enabled = false
    vpc_peering_connections = {
      shared = {
        peer_vpc_id      = "vpc-0123456789abcdef0"
        peer_cidr_blocks = ["10.50.0.0/16"]
      }
    }
  }

  assert {
    condition     = length(aws_vpc_peering_connection.this) == 1
    error_message = "Should create 1 VPC peering connection"
  }

  assert {
    condition     = aws_vpc_peering_connection.this["shared"].peer_vpc_id == "vpc-0123456789abcdef0"
    error_message = "Peering connection should target the configured peer VPC"
  }

  assert {
    condition     = aws_vpc_peering_connection.this["shared"].auto_accept == true
    error_message = "Same-account/region peering should auto-accept by default"
  }

  assert {
    condition     = length(aws_route.public_vpc_peering) == 1
    error_message = "Should create 1 public peering route"
  }

  assert {
    condition     = length(aws_route.private_vpc_peering) == 1
    error_message = "Should create 1 private peering route (single private RT)"
  }

  assert {
    condition     = aws_route.public_vpc_peering["shared-10.50.0.0/16"].destination_cidr_block == "10.50.0.0/16"
    error_message = "Public peering route should use the peer CIDR as destination"
  }
}

# Test 28: VPC peering with multi-AZ NAT (multiple private route tables)
run "vpc_peering_multi_private_route_tables" {
  command = plan

  variables {
    subnet_count                          = 3
    nat_gateway_enabled                   = true
    nat_gateway_high_availability_enabled = true
    vpc_peering_connections = {
      shared = {
        peer_vpc_id      = "vpc-0123456789abcdef0"
        peer_cidr_blocks = ["10.50.0.0/16", "10.51.0.0/16"]
      }
    }
  }

  assert {
    condition     = length(aws_route.public_vpc_peering) == 2
    error_message = "Should create 2 public peering routes (one per peer CIDR)"
  }

  assert {
    condition     = length(aws_route.private_vpc_peering) == 6
    error_message = "Should create 6 private peering routes (3 RTs x 2 peer CIDRs)"
  }
}

# Test 29: Cross-account VPC peering does not auto-accept
run "vpc_peering_cross_account" {
  command = plan

  variables {
    vpc_peering_connections = {
      external = {
        peer_vpc_id      = "vpc-0fedcba9876543210"
        peer_cidr_blocks = ["10.100.0.0/16"]
        peer_owner_id    = "111122223333"
      }
    }
  }

  assert {
    condition     = aws_vpc_peering_connection.this["external"].auto_accept == false
    error_message = "Cross-account peering must not auto-accept"
  }

  assert {
    condition     = aws_vpc_peering_connection.this["external"].peer_owner_id == "111122223333"
    error_message = "Cross-account peering should record the peer owner ID"
  }
}

# Test 30: Cross-region VPC peering does not auto-accept
run "vpc_peering_cross_region" {
  command = plan

  variables {
    vpc_peering_connections = {
      remote = {
        peer_vpc_id      = "vpc-0fedcba9876543210"
        peer_cidr_blocks = ["10.100.0.0/16"]
        peer_region      = "eu-west-1"
      }
    }
  }

  assert {
    condition     = aws_vpc_peering_connection.this["remote"].auto_accept == false
    error_message = "Cross-region peering must not auto-accept"
  }

  assert {
    condition     = aws_vpc_peering_connection.this["remote"].peer_region == "eu-west-1"
    error_message = "Cross-region peering should record the peer region"
  }
}

# Test 31: Peering with route placement disabled
run "vpc_peering_no_routes" {
  command = plan

  variables {
    vpc_peering_connections = {
      private-only = {
        peer_vpc_id                        = "vpc-0123456789abcdef0"
        peer_cidr_blocks                   = ["10.50.0.0/16"]
        public_route_table_routes_enabled  = false
        private_route_table_routes_enabled = true
      }
      none = {
        peer_vpc_id                        = "vpc-0123456789abcdee0"
        peer_cidr_blocks                   = ["10.60.0.0/16"]
        public_route_table_routes_enabled  = false
        private_route_table_routes_enabled = false
      }
    }
  }

  assert {
    condition     = length(aws_route.public_vpc_peering) == 0
    error_message = "Should not create public peering routes when disabled"
  }

  assert {
    condition     = length(aws_route.private_vpc_peering) == 1
    error_message = "Should only create the private route for the private-only peering"
  }
}

# Test 32: VPC peering connection options created when DNS resolution allowed
run "vpc_peering_dns_resolution" {
  command = plan

  variables {
    vpc_peering_connections = {
      shared = {
        peer_vpc_id                       = "vpc-0123456789abcdef0"
        peer_cidr_blocks                  = ["10.50.0.0/16"]
        remote_vpc_dns_resolution_enabled = true
      }
    }
  }

  assert {
    condition     = length(aws_vpc_peering_connection_options.requester) == 1
    error_message = "Should create requester options when DNS resolution is enabled"
  }
}

# Test 33: Peer-side return routes for same-account, same-region peering
run "vpc_peering_peer_route_tables" {
  command = plan

  variables {
    vpc_cidr = "10.0.0.0/16"
    vpc_peering_connections = {
      shared = {
        peer_vpc_id      = "vpc-0123456789abcdef0"
        peer_cidr_blocks = ["10.50.0.0/16"]
        peer_route_table_ids = [
          "rtb-0aaaa1111bbbb2222c",
          "rtb-0aaaa1111bbbb3333d",
        ]
      }
    }
  }

  assert {
    condition     = length(aws_route.peer_vpc_peering) == 2
    error_message = "Should create 1 peer-side route per peer route table"
  }

  assert {
    condition     = aws_route.peer_vpc_peering["shared-rtb-0aaaa1111bbbb2222c"].destination_cidr_block == "10.0.0.0/16"
    error_message = "Peer-side route destination should equal this VPC's CIDR"
  }

  assert {
    condition     = aws_route.peer_vpc_peering["shared-rtb-0aaaa1111bbbb2222c"].route_table_id == "rtb-0aaaa1111bbbb2222c"
    error_message = "Peer-side route should target the configured peer route table"
  }
}

# Test 34: No peer-side routes when peer_route_table_ids is empty
run "vpc_peering_no_peer_route_tables" {
  command = plan

  variables {
    vpc_peering_connections = {
      shared = {
        peer_vpc_id      = "vpc-0123456789abcdef0"
        peer_cidr_blocks = ["10.50.0.0/16"]
      }
    }
  }

  assert {
    condition     = length(aws_route.peer_vpc_peering) == 0
    error_message = "Should not create peer-side routes when peer_route_table_ids is empty"
  }
}

# Test 35: peer_route_table_ids rejected for cross-account peering
run "vpc_peering_peer_routes_cross_account_rejected" {
  command = plan

  variables {
    vpc_peering_connections = {
      external = {
        peer_vpc_id          = "vpc-0123456789abcdef0"
        peer_cidr_blocks     = ["10.50.0.0/16"]
        peer_owner_id        = "111122223333"
        peer_route_table_ids = ["rtb-0aaaa1111bbbb2222c"]
      }
    }
  }

  expect_failures = [
    var.vpc_peering_connections,
  ]
}

# Test 36: Multiple peering connections
run "vpc_peering_multiple" {
  command = plan

  variables {
    vpc_peering_connections = {
      shared = {
        peer_vpc_id      = "vpc-0123456789abcdef0"
        peer_cidr_blocks = ["10.50.0.0/16"]
      }
      data = {
        peer_vpc_id      = "vpc-0aaaa1111bbbb2222c"
        peer_cidr_blocks = ["10.60.0.0/16"]
      }
    }
  }

  assert {
    condition     = length(aws_vpc_peering_connection.this) == 2
    error_message = "Should create 2 VPC peering connections"
  }

  assert {
    condition     = length(aws_route.public_vpc_peering) == 2
    error_message = "Should create 1 public peering route per connection"
  }
}

# Private subnet groups: none by default, and no endpoint without a flag
run "private_subnet_groups_default" {
  command = plan

  assert {
    condition     = length(aws_subnet.private_group) == 0 && length(aws_route_table.private_group) == 0
    error_message = "No private subnet groups should be created by default"
  }

  assert {
    condition     = length(aws_vpc_endpoint.s3) == 0 && length(aws_vpc_endpoint.dynamodb) == 0
    error_message = "No gateway endpoints should be created by default"
  }
}

# A group with the S3 endpoint gets it on its own route table only
run "private_subnet_group_s3_endpoint_only" {
  command = apply

  variables {
    nat_gateway_enabled                   = true
    subnet_count                          = 3
    nat_gateway_high_availability_enabled = false
    vpc_endpoint_s3_gateway_subnets       = ["builds"]
    private_subnet_groups = {
      builds = {
        cidrs = ["10.0.21.0/24", "10.0.22.0/24", "10.0.23.0/24"]
      }
    }
  }

  assert {
    condition     = [for index in range(3) : aws_subnet.private_group["builds-${index}"].cidr_block] == ["10.0.21.0/24", "10.0.22.0/24", "10.0.23.0/24"]
    error_message = "Group subnets should take the given CIDRs in availability zone order"
  }

  assert {
    condition     = [for index in range(3) : aws_subnet.private_group["builds-${index}"].availability_zone] == aws_subnet.private[*].availability_zone
    error_message = "Group subnets should be in the same availability zones as the private subnets"
  }

  assert {
    condition     = length(aws_route_table.private_group) == 1 && length(aws_route_table_association.private_group) == 3
    error_message = "A group should share one route table across its subnets with a single NAT gateway"
  }

  assert {
    condition     = aws_route.private_group_nat["builds-0"].nat_gateway_id == aws_nat_gateway.this[0].id
    error_message = "The group route table should route to the NAT gateway"
  }

  assert {
    condition     = toset(aws_vpc_endpoint.s3[0].route_table_ids) == toset([aws_route_table.private_group["builds-0"].id])
    error_message = "The S3 endpoint should attach to the group route table only, leaving the public and private route tables on the NAT gateway"
  }

  assert {
    condition     = length(aws_vpc_endpoint.dynamodb) == 0
    error_message = "The DynamoDB endpoint should not be created when it names no subnets"
  }

  assert {
    condition     = output.vpc_endpoint_s3_id == aws_vpc_endpoint.s3[0].id
    error_message = "vpc_endpoint_s3_id should name the endpoint the group routes through"
  }

  assert {
    condition     = output.private_subnet_group_subnet_ids["builds"] == [for index in range(3) : aws_subnet.private_group["builds-${index}"].id]
    error_message = "private_subnet_group_subnet_ids should list the group's subnets in availability zone order"
  }
}

# Naming the public and private subnets attaches the endpoint to their route
# tables, and a group the list leaves out stays on the NAT gateway
run "private_subnet_group_left_out_of_the_s3_endpoint" {
  command = apply

  variables {
    subnet_count                    = 2
    vpc_endpoint_s3_gateway_subnets = ["public", "private"]
    private_subnet_groups = {
      jobs = {
        cidrs = ["10.0.21.0/24", "10.0.22.0/24"]
      }
    }
  }

  assert {
    condition     = toset(aws_vpc_endpoint.s3[0].route_table_ids) == toset(concat([aws_route_table.public.id], aws_route_table.private[*].id))
    error_message = "The S3 endpoint should attach to the public and private route tables, not the group's"
  }
}

# Both endpoints, two groups
run "private_subnet_groups_dynamodb_endpoint" {
  command = apply

  variables {
    subnet_count                          = 2
    vpc_endpoint_s3_gateway_subnets       = ["builds"]
    vpc_endpoint_dynamodb_gateway_subnets = ["builds", "jobs"]
    private_subnet_groups = {
      builds = {
        cidrs = ["10.0.21.0/24", "10.0.22.0/24"]
      }
      jobs = {
        cidrs = ["10.0.31.0/24", "10.0.32.0/24"]
      }
    }
  }

  assert {
    condition     = toset(aws_vpc_endpoint.s3[0].route_table_ids) == toset([aws_route_table.private_group["builds-0"].id])
    error_message = "Only the builds group should route S3 through the endpoint"
  }

  assert {
    condition     = toset(aws_vpc_endpoint.dynamodb[0].route_table_ids) == toset([aws_route_table.private_group["builds-0"].id, aws_route_table.private_group["jobs-0"].id])
    error_message = "Both groups should route DynamoDB through the endpoint"
  }
}

# With highly available NAT gateways, a group gets a route table per AZ, each
# routed to the NAT gateway in its AZ
run "private_subnet_group_nat_ha" {
  command = apply

  variables {
    nat_gateway_enabled                   = true
    subnet_count                          = 3
    nat_gateway_high_availability_enabled = true
    private_subnet_groups = {
      builds = {
        cidrs = ["10.0.21.0/24", "10.0.22.0/24", "10.0.23.0/24"]
      }
    }
  }

  assert {
    condition     = length(aws_route_table.private_group) == 3
    error_message = "A group should get one route table per AZ with highly available NAT gateways"
  }

  assert {
    condition = alltrue([
      for index in range(3) : aws_route.private_group_nat["builds-${index}"].nat_gateway_id == aws_nat_gateway.this[index].id
    ])
    error_message = "Each group route table should route to the NAT gateway in its AZ"
  }

  assert {
    condition = alltrue([
      for index in range(3) : aws_route_table_association.private_group["builds-${index}"].route_table_id == aws_route_table.private_group["builds-${index}"].id
    ])
    error_message = "Each group subnet should use its own AZ's route table"
  }
}

# Without a NAT gateway, group route tables have no default route
run "private_subnet_group_nat_disabled" {
  command = plan

  variables {
    subnet_count        = 2
    nat_gateway_enabled = false
    private_subnet_groups = {
      builds = {
        cidrs = ["10.0.21.0/24", "10.0.22.0/24"]
      }
    }
  }

  assert {
    condition     = length(aws_route.private_group_nat) == 0
    error_message = "No NAT routes should be created without a NAT gateway"
  }
}

# Group route tables take the private peering routes
run "private_subnet_group_vpc_peering" {
  command = plan

  variables {
    subnet_count = 2
    private_subnet_groups = {
      builds = {
        cidrs = ["10.0.21.0/24", "10.0.22.0/24"]
      }
    }
    vpc_peering_connections = {
      shared = {
        peer_vpc_id      = "vpc-0123456789abcdef0"
        peer_cidr_blocks = ["10.50.0.0/16", "10.51.0.0/16"]
      }
      public_only = {
        peer_vpc_id                        = "vpc-0fedcba9876543210"
        peer_cidr_blocks                   = ["10.60.0.0/16"]
        private_route_table_routes_enabled = false
      }
    }
  }

  assert {
    condition     = length(aws_route.private_group_vpc_peering) == 2
    error_message = "The group route table should get one route per peer CIDR of peerings with private routes enabled"
  }
}

# A group needs one CIDR per subnet pair
run "private_subnet_group_wrong_cidr_count" {
  command = plan

  variables {
    subnet_count = 3
    private_subnet_groups = {
      builds = {
        cidrs = ["10.0.21.0/24", "10.0.22.0/24"]
      }
    }
  }

  expect_failures = [aws_subnet.private_group]
}

run "private_subnet_group_invalid_name" {
  command = plan

  variables {
    private_subnet_groups = {
      "Builds_Group" = {
        cidrs = ["10.0.21.0/24", "10.0.22.0/24", "10.0.23.0/24"]
      }
    }
  }

  expect_failures = [var.private_subnet_groups]
}

# The private subnets and a group can share an endpoint, and the public subnets
# stay on the NAT gateway when the list leaves them out
run "s3_endpoint_on_the_private_subnets_and_a_group" {
  command = apply

  variables {
    subnet_count                    = 2
    vpc_endpoint_s3_gateway_subnets = ["private", "builds"]
    private_subnet_groups = {
      builds = {
        cidrs = ["10.0.21.0/24", "10.0.22.0/24"]
      }
    }
  }

  assert {
    condition     = toset(aws_vpc_endpoint.s3[0].route_table_ids) == toset(concat(aws_route_table.private[*].id, [aws_route_table.private_group["builds-0"].id]))
    error_message = "The S3 endpoint should attach to the private route tables and the builds group's, not the public one"
  }
}

# A name that is neither public, private nor a group is refused
run "gateway_endpoint_unknown_subnets" {
  command = plan

  variables {
    vpc_endpoint_s3_gateway_subnets = ["sandbox"]
  }

  expect_failures = [aws_vpc_endpoint.s3]
}

# public and private name the VPC's own subnets, so no group may take them
run "private_subnet_group_reserved_name" {
  command = plan

  variables {
    private_subnet_groups = {
      private = {
        cidrs = ["10.0.21.0/24", "10.0.22.0/24", "10.0.23.0/24"]
      }
    }
  }

  expect_failures = [var.private_subnet_groups]
}
