mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-2" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_subnet" {
    defaults = { vpc_id = "vpc-12345678", availability_zone = "us-east-2a" }
  }
  # Downstream validation rules check ARN shapes, which the generated mock
  # values do not satisfy.
  mock_resource "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:us-east-2:123456789012:cluster/test-cluster"
      endpoint              = "https://mock.eks.amazonaws.com"
      version               = "1.33"
      certificate_authority = [{ data = "bW9jay1jYQ==" }]
      identity              = [{ oidc = [{ issuer = "https://oidc.eks.us-east-2.amazonaws.com/id/MOCK" }] }]
    }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mock" }
  }
  mock_resource "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::123456789012:policy/mock" }
  }
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-east-2:123456789012:key/00000000-0000-0000-0000-000000000000", key_id = "00000000-0000-0000-0000-000000000000" }
  }
}

variables {
  name       = "test-cluster"
  region     = "us-east-2"
  vpc_id     = "vpc-12345678"
  subnet_ids = ["subnet-0a", "subnet-0b"]
}

run "coredns_spread_across_zones_by_default" {
  command = plan
  assert {
    condition     = jsondecode(local.coredns_addon_configuration_values).topologySpreadConstraints[0].topologyKey == "topology.kubernetes.io/zone"
    error_message = "CoreDNS must be spread across availability zones by default."
  }
  assert {
    condition     = jsondecode(local.coredns_addon_configuration_values).topologySpreadConstraints[0].whenUnsatisfiable == "ScheduleAnyway"
    error_message = "The spread must stay a soft preference so DNS never goes pending on a small cluster."
  }
  assert {
    condition     = jsondecode(local.coredns_addon_configuration_values).topologySpreadConstraints[0].labelSelector.matchLabels["k8s-app"] == "kube-dns"
    error_message = "The spread must select the CoreDNS pods."
  }
  assert {
    condition     = output.topology_aware_routing_enabled == true
    error_message = "The cluster must publish the zone-local routing default for the add-ons stack."
  }
}

run "explicit_coredns_configuration_wins" {
  command = plan
  variables {
    coredns_addon_configuration_values = "{\"replicaCount\":3}"
  }
  assert {
    condition     = local.coredns_addon_configuration_values == "{\"replicaCount\":3}"
    error_message = "An explicit CoreDNS configuration document must replace the default spread untouched."
  }
}

run "disabled" {
  command = plan
  variables {
    topology_aware_routing_enabled = false
  }
  assert {
    condition     = local.coredns_addon_configuration_values == null
    error_message = "Disabling zone-local routing must leave CoreDNS on the add-on defaults."
  }
  assert {
    condition     = output.topology_aware_routing_enabled == false
    error_message = "The published default must follow the flag."
  }
}
