mock_provider "aws" {}

variables {
  cluster_name = "test-cluster"
}

run "metrics_server_installs_as_eks_addon_by_default" {
  command = plan

  assert {
    condition     = length(aws_eks_addon.metrics_server) == 1 && aws_eks_addon.metrics_server[0].addon_name == "metrics-server"
    error_message = "The default post-compute stack must create the Metrics Server EKS community add-on"
  }

  assert {
    condition     = var.metrics_server_addon_version == null && aws_eks_addon.metrics_server[0].resolve_conflicts_on_create == "NONE"
    error_message = "Let EKS choose a compatible version at creation, without adopting a self-managed installation"
  }
}

run "metrics_server_can_be_disabled" {
  command = plan

  variables {
    metrics_server_enabled = false
  }

  assert {
    condition     = length(aws_eks_addon.metrics_server) == 0 && output.metrics_server_addon_arn == null && output.metrics_server_addon_version == null
    error_message = "Disabling Metrics Server must omit its add-on and outputs"
  }
}

run "metrics_server_accepts_explicit_version_and_configuration" {
  command = plan

  variables {
    metrics_server_addon_version              = "v0.8.0-eksbuild.1"
    metrics_server_addon_configuration_values = "{}"
  }

  assert {
    condition     = aws_eks_addon.metrics_server[0].addon_version == "v0.8.0-eksbuild.1" && aws_eks_addon.metrics_server[0].configuration_values == "{}"
    error_message = "The cluster must pass explicit version and configuration overrides to EKS"
  }
}
