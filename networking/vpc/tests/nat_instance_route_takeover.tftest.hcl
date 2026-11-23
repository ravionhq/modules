# NAT instance route takeover tests
# Run with: tofu test
#
# Runs in this file share state, in order: a VPC first deploys without the
# input, then turns it on while a NAT instance holds the default routes.
#
# aws_route.network_interface_id is optional and computed, so on routes that
# target a NAT gateway the mock provider fills it with a random value. Those
# runs check nat_gateway_id only.

mock_provider "aws" {
  override_data {
    target = data.aws_availability_zones.available
    values = {
      names = ["us-east-1a", "us-east-1b"]
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
      id     = "us-east-1"
      name   = "us-east-1"
      region = "us-east-1"
    }
  }
}

variables {
  name                                  = "test-vpc"
  flow_logs_enabled                     = false
  nat_gateway_enabled                   = true
  nat_gateway_high_availability_enabled = true
}

run "default_routes_target_nat_gateways" {
  assert {
    condition     = length(data.aws_route_table.private_nat_live) == 0
    error_message = "Live private route tables must not be read unless nat_instance_route_takeover_enabled is true."
  }

  assert {
    condition = alltrue([
      for i, route in aws_route.private_nat :
      route.nat_gateway_id == aws_nat_gateway.this[i].id
    ])
    error_message = "Without nat_instance_route_takeover_enabled, every private default route must target its NAT gateway."
  }
}

# A NAT instance has taken over the default routes.
run "takeover_keeps_nat_instance_targets" {
  command = plan

  variables {
    nat_instance_route_takeover_enabled = true
  }

  override_data {
    target = data.aws_route_table.private_nat_live
    values = {
      routes = [
        {
          cidr_block                 = "0.0.0.0/0"
          network_interface_id       = "eni-0aaaaaaaaaaaaaaa1"
          nat_gateway_id             = ""
          ipv6_cidr_block            = ""
          destination_prefix_list_id = ""
          carrier_gateway_id         = ""
          core_network_arn           = ""
          egress_only_gateway_id     = ""
          gateway_id                 = ""
          instance_id                = "i-0aaaaaaaaaaaaaaa1"
          local_gateway_id           = ""
          odb_network_arn            = ""
          transit_gateway_id         = ""
          vpc_endpoint_id            = ""
          vpc_peering_connection_id  = ""
        },
      ]
    }
  }

  assert {
    condition = alltrue([
      for route in aws_route.private_nat :
      route.network_interface_id == "eni-0aaaaaaaaaaaaaaa1" && route.nat_gateway_id == null
    ])
    error_message = "A default route held by a NAT instance must keep its network interface target."
  }

  # Turning the input on must update the existing routes in place: deleting a
  # route cuts off egress. A replaced route has an unknown ID at plan time,
  # which fails this assertion.
  assert {
    condition     = alltrue([for route in aws_route.private_nat : route.id != ""])
    error_message = "Turning on nat_instance_route_takeover_enabled must not replace the private default routes."
  }
}

# A route on a NAT gateway, including one that no longer exists, points at the
# module's NAT gateway. Network interface routes to other destinations are not
# a takeover.
run "takeover_repoints_nat_gateway_routes" {
  command = plan

  variables {
    nat_instance_route_takeover_enabled = true
  }

  override_data {
    target = data.aws_route_table.private_nat_live
    values = {
      routes = [
        {
          cidr_block                 = "0.0.0.0/0"
          network_interface_id       = ""
          nat_gateway_id             = "nat-0deleted000000001"
          ipv6_cidr_block            = ""
          destination_prefix_list_id = ""
          carrier_gateway_id         = ""
          core_network_arn           = ""
          egress_only_gateway_id     = ""
          gateway_id                 = ""
          instance_id                = ""
          local_gateway_id           = ""
          odb_network_arn            = ""
          transit_gateway_id         = ""
          vpc_endpoint_id            = ""
          vpc_peering_connection_id  = ""
        },
        {
          cidr_block                 = "10.1.0.0/16"
          network_interface_id       = "eni-0bbbbbbbbbbbbbbb2"
          nat_gateway_id             = ""
          ipv6_cidr_block            = ""
          destination_prefix_list_id = ""
          carrier_gateway_id         = ""
          core_network_arn           = ""
          egress_only_gateway_id     = ""
          gateway_id                 = ""
          instance_id                = ""
          local_gateway_id           = ""
          odb_network_arn            = ""
          transit_gateway_id         = ""
          vpc_endpoint_id            = ""
          vpc_peering_connection_id  = ""
        },
      ]
    }
  }

  assert {
    condition = alltrue([
      for i, route in aws_route.private_nat :
      route.nat_gateway_id == aws_nat_gateway.this[i].id
    ])
    error_message = "Default routes not held by a NAT instance must target the module's NAT gateways."
  }
}

# A new VPC has no default route yet, so it is created on the NAT gateway.
run "takeover_creates_missing_routes_on_nat_gateway" {
  command = plan

  variables {
    nat_instance_route_takeover_enabled = true
  }

  override_data {
    target = data.aws_route_table.private_nat_live
    values = {
      routes = []
    }
  }

  assert {
    condition = alltrue([
      for i, route in aws_route.private_nat :
      route.nat_gateway_id == aws_nat_gateway.this[i].id
    ])
    error_message = "A missing default route must be created on the module's NAT gateway."
  }
}
