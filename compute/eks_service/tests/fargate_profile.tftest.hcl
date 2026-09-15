################################################################################
# Workload Fargate profile
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
      id     = "us-east-1"
      name   = "us-east-1"
      region = "us-east-1"
    }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
  mock_data "aws_lb_listener" {
    defaults = {
      load_balancer_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test/1234567890abcdef"
    }
  }
  mock_data "aws_lb" {
    defaults = {
      dns_name = "test.us-east-1.elb.amazonaws.com"
      zone_id  = "Z35SXDOTRQ7X7K"
    }
  }
  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/test/1234567890abcdef"
    }
  }
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock-fargate-pod-execution-role"
    }
  }
  mock_resource "aws_eks_fargate_profile" {
    defaults = {
      arn    = "arn:aws:eks:us-east-1:123456789012:fargateprofile/test-cluster/test-workload-fargate/12345678-1234-1234-1234-123456789012"
      status = "ACTIVE"
    }
  }
}

variables {
  name   = "test-workload"
  region = "us-east-1"
  vpc_id = "vpc-0123456789abcdef0"
}

run "fargate_profile_disabled_by_default" {
  command = plan

  assert {
    condition     = output.fargate_profile_name == null && output.fargate_profile_arn == null
    error_message = "The workload must not create or expose a Fargate profile by default."
  }
}

run "creates_workload_fargate_profile" {
  command = plan

  variables {
    cluster_name = "test-cluster"
    fargate_profile = {
      name       = "test-workload-fargate"
      subnet_ids = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
      selectors = [{
        namespace = "test"
        labels = {
          "app.kubernetes.io/instance" = "test-workload"
        }
      }]
    }
  }

  assert {
    condition     = output.fargate_profile_name == "test-workload-fargate"
    error_message = "The workload must expose the generated Fargate profile name."
  }

  assert {
    condition     = output.fargate_profile_arn != null
    error_message = "The workload must expose the generated Fargate profile ARN."
  }
}

run "supports_long_cluster_and_workload_names" {
  command = plan

  variables {
    cluster_name = "test-cluster-with-a-deliberately-long-name"
    fargate_profile = {
      name       = "test-workload-with-a-deliberately-long-name-fargate"
      subnet_ids = ["subnet-0123456789abcdef0"]
      selectors = [{
        namespace = "test"
        labels = {
          "app.kubernetes.io/instance" = "test-workload-with-a-deliberately-long-name"
        }
      }]
    }
  }

  assert {
    condition     = output.fargate_profile_name == "test-workload-with-a-deliberately-long-name-fargate"
    error_message = "The profile name must remain stable when its generated pod execution role name needs shortening."
  }
}

run "hashes_long_target_group_names" {
  command = plan

  variables {
    name         = "shared-prefix-for-two-workloads-alpha"
    listener_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/test/1234567890abcdef/1234567890abcdef"
  }

  assert {
    condition     = output.target_group_name == "shared-prefix-for-tw-${substr(sha1("shared-prefix-for-two-workloads-alpha"), 0, 8)}-tg"
    error_message = "Long target group names must include a stable hash within the ELBv2 name limit."
  }
}

run "rejects_empty_fargate_selectors" {
  command = plan

  variables {
    cluster_name = "test-cluster"
    fargate_profile = {
      name       = "test-workload-fargate"
      subnet_ids = ["subnet-0123456789abcdef0"]
      selectors  = []
    }
  }

  expect_failures = [var.fargate_profile]
}

run "rejects_fargate_profile_without_cluster" {
  command = plan

  variables {
    fargate_profile = {
      name       = "test-workload-fargate"
      subnet_ids = ["subnet-0123456789abcdef0"]
      selectors = [{
        namespace = "test"
        labels = {
          "app.kubernetes.io/instance" = "test-workload"
        }
      }]
    }
  }

  expect_failures = [var.fargate_profile]
}

run "rejects_invalid_fargate_profile_name" {
  command = plan

  variables {
    cluster_name = "test-cluster"
    fargate_profile = {
      name       = "invalid profile name"
      subnet_ids = ["subnet-0123456789abcdef0"]
      selectors = [{
        namespace = "test"
        labels = {
          "app.kubernetes.io/instance" = "test-workload"
        }
      }]
    }
  }

  expect_failures = [var.fargate_profile]
}
