################################################################################
# Amazon Managed Prometheus workspace + remote-write identity
#
# One workspace per cluster, in the customer's own account, holding the curated
# workload metrics the collector remote-writes (see otel_collector.tf). PromQL
# is the query surface for both the Ravion dashboard and any Grafana pointed at
# it, which is why the metrics do not go to CloudWatch alongside the logs.
#
# Three things about the shape of this file:
#
#   1. THE WORKSPACE IS OPTIONAL TO CREATE, NOT OPTIONAL TO HAVE. Setting
#      amp_workspace_id brings an existing workspace and suppresses creation;
#      everything downstream reads the locals below, so neither the collector
#      nor the IAM policy branches on which case it is.
#
#   2. THE REGION IS A RESOURCE ARGUMENT, NOT A PROVIDER ALIAS. AMP is not in
#      every region an EKS cluster can run in, and remote write works
#      cross-region. The AWS provider's per-resource `region` covers that
#      without a second provider configuration.
#
#   3. IAM IS POD IDENTITY, scoped to this one workspace ARN — the house
#      pattern, and the reason the collector carries no static credentials.
################################################################################

locals {
  amp_create = local.amp_enabled && local.amp_config.workspace_id == null

  # data.aws_region.current is never null, so this always resolves.
  amp_region = coalesce(local.amp_config.region, var.region, data.aws_region.current.region)
  amp_alias  = coalesce(local.amp_config.alias, "ravion-${var.cluster_name}")

  amp_workspace_id = local.amp_enabled ? (
    local.amp_create ? aws_prometheus_workspace.this[0].id : local.amp_config.workspace_id
  ) : null

  # Constructed rather than read back for the bring-your-own case: a data source
  # would make every plan depend on the workspace still existing, and the ARN of
  # an AMP workspace is fully determined by account, region, and id.
  amp_workspace_arn = local.amp_enabled ? (
    local.amp_create
    ? aws_prometheus_workspace.this[0].arn
    : "arn:${data.aws_partition.current.partition}:aps:${local.amp_region}:${data.aws_caller_identity.current.account_id}:workspace/${local.amp_config.workspace_id}"
  ) : null

  # The Prometheus-compatible base URL. Grafana and the Ravion dashboard take it
  # as-is; the collector appends the remote-write path.
  amp_query_endpoint = local.amp_enabled ? (
    "https://aps-workspaces.${local.amp_region}.${data.aws_partition.current.dns_suffix}/workspaces/${local.amp_workspace_id}"
  ) : null

  amp_remote_write_endpoint = local.amp_enabled ? "${local.amp_query_endpoint}/api/v1/remote_write" : null
}

resource "aws_prometheus_workspace" "this" {
  count = local.amp_create ? 1 : 0

  # Null means the provider's own region, which is the cluster's region.
  region = local.amp_config.region

  alias = local.amp_alias

  tags = local.tags
}

################################################################################
# Collector write identity
################################################################################

data "aws_iam_policy_document" "amp_remote_write" {
  count = local.amp_enabled ? 1 : 0

  statement {
    sid       = "RemoteWriteToWorkspace"
    effect    = "Allow"
    actions   = ["aps:RemoteWrite"]
    resources = [local.amp_workspace_arn]
  }
}

module "amp_remote_write_role" {
  count = local.amp_enabled ? 1 : 0

  source = "../../../security/iam"

  name        = "${var.cluster_name}-amp-remote-write"
  description = "AMP remote-write Pod Identity role for the metrics collector on ${var.cluster_name}"

  custom_assume_role_policy = local.pod_identity_trust_policy

  inline_policies = {
    "amp-remote-write" = data.aws_iam_policy_document.amp_remote_write[0].json
  }

  tags = local.tags
}

# Binds the role to the collector's service account. The collector resolves
# credentials through the AWS SDK default credential chain, which the Pod
# Identity Agent populates — the sigv4auth extension configures no credentials
# of its own.
resource "aws_eks_pod_identity_association" "otel_collector" {
  count = local.amp_enabled ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = local.metrics_namespace
  service_account = var.otel_collector_service_account
  role_arn        = module.amp_remote_write_role[0].role_arn

  tags = local.tags
}
