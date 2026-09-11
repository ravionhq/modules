################################################################################
# AWS Load Balancer Controller
################################################################################

output "lb_controller_chart_version" {
  description = "Installed version of the aws-load-balancer-controller Helm chart (null if disabled)."
  value       = local.lb_controller_install ? helm_release.lb_controller[0].version : null
}

output "lb_controller_namespace" {
  description = "Namespace where the AWS Load Balancer Controller is installed (null if disabled)."
  value       = local.lb_controller_install ? helm_release.lb_controller[0].namespace : null
}

################################################################################
# EBS CSI Driver
################################################################################

output "ebs_csi_addon_version" {
  description = "Resolved version of the aws-ebs-csi-driver EKS add-on (null if disabled)."
  value       = var.ebs_csi_driver_enabled ? aws_eks_addon.ebs_csi[0].addon_version : null
}

output "ebs_csi_role_arn" {
  description = "ARN of the EBS CSI driver Pod Identity role (null if disabled)."
  value       = var.ebs_csi_driver_enabled ? module.ebs_csi_role[0].role_arn : null
}

################################################################################
# CloudWatch Observability
################################################################################

output "cloudwatch_observability_addon_version" {
  description = "Resolved version of the amazon-cloudwatch-observability EKS add-on (null unless cloudwatch is in logs_providers or metrics_providers)."
  value       = local.cloudwatch_addon_enabled ? aws_eks_addon.cloudwatch_observability[0].addon_version : null
}

output "cloudwatch_observability_role_arn" {
  description = "ARN of the CloudWatch Observability add-on Pod Identity role (null unless the add-on is installed)."
  value       = local.cloudwatch_addon_enabled ? module.cloudwatch_observability_role[0].role_arn : null
}

output "cloudwatch_application_signals_namespaces" {
  description = "Namespaces Application Signals auto-instrumentation was asked for. The add-on's cluster-wide Auto-Monitor stays OFF when this is non-empty: annotate these namespaces with instrumentation.opentelemetry.io/inject-* to instrument exactly them. Empty list when Application Signals is off or when it was enabled cluster-wide."
  value       = local.cloudwatch_metrics_config.application_signals_namespaces
}

################################################################################
# External Secrets Operator
################################################################################

output "eso_namespace" {
  description = "Kubernetes namespace where the External Secrets Operator is installed (null if disabled)."
  value       = var.eso_enabled ? helm_release.external_secrets[0].namespace : null
}

output "eso_chart_version" {
  description = "Installed version of the external-secrets Helm chart (null if disabled)."
  value       = var.eso_enabled ? helm_release.external_secrets[0].version : null
}

output "eso_role_arn" {
  description = "ARN of the External Secrets Operator Pod Identity role (null if disabled)."
  value       = var.eso_enabled ? module.external_secrets_role[0].role_arn : null
}

output "eso_secrets_manager_store_name" {
  description = "Name of the cluster-scoped AWS Secrets Manager store (kind ClusterSecretStore, apiVersion external-secrets.io/v1) that workload charts reference for Secrets Manager secrets (null if disabled)."
  value       = var.eso_enabled && var.eso_cluster_secret_stores_creation_enabled ? var.eso_secrets_manager_store_name : null
}

output "eso_parameter_store_store_name" {
  description = "Name of the cluster-scoped AWS SSM Parameter Store store (kind ClusterSecretStore, apiVersion external-secrets.io/v1) that workload charts reference for SSM parameters (null if disabled)."
  value       = var.eso_enabled && var.eso_cluster_secret_stores_creation_enabled ? var.eso_parameter_store_store_name : null
}

################################################################################
# Karpenter
################################################################################

output "karpenter_namespace" {
  description = "Kubernetes namespace where the Karpenter controller is installed (null if disabled)."
  value       = var.karpenter_enabled ? helm_release.karpenter[0].namespace : null
}

output "karpenter_chart_version" {
  description = "Installed version of the Karpenter Helm chart (null if disabled)."
  value       = var.karpenter_enabled ? helm_release.karpenter[0].version : null
}

output "karpenter_default_node_pool_release" {
  description = "Helm release name of the default NodePool chart (null if disabled)."
  value       = var.karpenter_enabled && var.karpenter_default_node_pool_creation_enabled ? helm_release.karpenter_default_node_pool[0].name : null
}

output "karpenter_controller_role_arn" {
  description = "ARN of the Karpenter controller IAM role (null if disabled)."
  value       = var.karpenter_enabled ? module.karpenter[0].controller_role_arn : null
}

output "karpenter_node_role_arn" {
  description = "ARN of the IAM role attached to Karpenter-launched nodes (null if disabled)."
  value       = var.karpenter_enabled ? module.karpenter[0].node_role_arn : null
}

output "karpenter_node_instance_profile_name" {
  description = "Instance profile name used by the default EC2NodeClass (null if disabled)."
  value       = var.karpenter_enabled ? module.karpenter[0].node_instance_profile_name : null
}

output "karpenter_interruption_queue_name" {
  description = "Name of the SQS interruption queue (null if disabled)."
  value       = var.karpenter_enabled ? module.karpenter[0].interruption_queue_name : null
}

################################################################################
# Shared Load Balancers
################################################################################

output "public_alb_arn" {
  description = "ARN of the shared public ALB (null if disabled)."
  value       = var.public_alb_creation_enabled ? module.public_alb[0].alb_arn : null
}

output "public_alb_dns_name" {
  description = "DNS name of the shared public ALB (null if disabled)."
  value       = var.public_alb_creation_enabled ? module.public_alb[0].alb_dns_name : null
}

output "public_alb_zone_id" {
  description = "Route 53 zone ID of the shared public ALB (null if disabled)."
  value       = var.public_alb_creation_enabled ? module.public_alb[0].alb_zone_id : null
}

output "public_alb_arn_suffix" {
  description = "ARN suffix of the shared public ALB, for CloudWatch metrics (null if disabled)."
  value       = var.public_alb_creation_enabled ? module.public_alb[0].alb_arn_suffix : null
}

output "public_alb_security_group_id" {
  description = "Security group ID of the shared public ALB (null if disabled)."
  value       = var.public_alb_creation_enabled ? module.public_alb[0].security_group_id : null
}

output "public_alb_http_listener_arn" {
  description = "ARN of the shared public ALB HTTP listener (null if disabled)."
  value       = var.public_alb_creation_enabled ? module.public_alb[0].http_listener_arn : null
}

output "public_alb_https_listener_arn" {
  description = "ARN of the shared public ALB HTTPS listener (null if disabled)."
  value       = var.public_alb_creation_enabled ? module.public_alb[0].https_listener_arn : null
}

output "private_alb_arn" {
  description = "ARN of the shared private ALB (null if disabled)."
  value       = var.private_alb_creation_enabled ? module.private_alb[0].alb_arn : null
}

output "private_alb_dns_name" {
  description = "DNS name of the shared private ALB (null if disabled)."
  value       = var.private_alb_creation_enabled ? module.private_alb[0].alb_dns_name : null
}

output "private_alb_zone_id" {
  description = "Route 53 zone ID of the shared private ALB (null if disabled)."
  value       = var.private_alb_creation_enabled ? module.private_alb[0].alb_zone_id : null
}

output "private_alb_arn_suffix" {
  description = "ARN suffix of the shared private ALB, for CloudWatch metrics (null if disabled)."
  value       = var.private_alb_creation_enabled ? module.private_alb[0].alb_arn_suffix : null
}

output "private_alb_security_group_id" {
  description = "Security group ID of the shared private ALB (null if disabled)."
  value       = var.private_alb_creation_enabled ? module.private_alb[0].security_group_id : null
}

output "private_alb_http_listener_arn" {
  description = "ARN of the shared private ALB HTTP listener (null if disabled)."
  value       = var.private_alb_creation_enabled ? module.private_alb[0].http_listener_arn : null
}

output "private_alb_https_listener_arn" {
  description = "ARN of the shared private ALB HTTPS listener (null if disabled)."
  value       = var.private_alb_creation_enabled ? module.private_alb[0].https_listener_arn : null
}

output "public_nlb_arn" {
  description = "ARN of the shared public NLB (null if disabled)."
  value       = var.public_nlb_creation_enabled ? module.public_nlb[0].nlb_arn : null
}

output "public_nlb_dns_name" {
  description = "DNS name of the shared public NLB (null if disabled)."
  value       = var.public_nlb_creation_enabled ? module.public_nlb[0].nlb_dns_name : null
}

output "public_nlb_zone_id" {
  description = "Route 53 zone ID of the shared public NLB (null if disabled)."
  value       = var.public_nlb_creation_enabled ? module.public_nlb[0].nlb_zone_id : null
}

output "public_nlb_arn_suffix" {
  description = "ARN suffix of the shared public NLB, for CloudWatch metrics (null if disabled)."
  value       = var.public_nlb_creation_enabled ? module.public_nlb[0].nlb_arn_suffix : null
}

output "public_nlb_security_group_id" {
  description = "Security group ID of the shared public NLB (null if disabled)."
  value       = var.public_nlb_creation_enabled ? module.public_nlb[0].security_group_id : null
}

output "private_nlb_arn" {
  description = "ARN of the shared private NLB (null if disabled)."
  value       = var.private_nlb_creation_enabled ? module.private_nlb[0].nlb_arn : null
}

output "private_nlb_dns_name" {
  description = "DNS name of the shared private NLB (null if disabled)."
  value       = var.private_nlb_creation_enabled ? module.private_nlb[0].nlb_dns_name : null
}

output "private_nlb_zone_id" {
  description = "Route 53 zone ID of the shared private NLB (null if disabled)."
  value       = var.private_nlb_creation_enabled ? module.private_nlb[0].nlb_zone_id : null
}

output "private_nlb_arn_suffix" {
  description = "ARN suffix of the shared private NLB, for CloudWatch metrics (null if disabled)."
  value       = var.private_nlb_creation_enabled ? module.private_nlb[0].nlb_arn_suffix : null
}

output "private_nlb_security_group_id" {
  description = "Security group ID of the shared private NLB (null if disabled)."
  value       = var.private_nlb_creation_enabled ? module.private_nlb[0].security_group_id : null
}

################################################################################
# Ravion Operator
################################################################################

output "ravion_operator_namespace" {
  description = "Kubernetes namespace where the Ravion Operator is installed (null if disabled)."
  value       = var.ravion_operator_enabled ? helm_release.ravion_operator[0].namespace : null
}

output "ravion_operator_chart_version" {
  description = "Installed version of the Ravion Operator Helm chart (null if disabled). This is the chart version, not the running agent version — the control plane owns that."
  value       = var.ravion_operator_enabled ? helm_release.ravion_operator[0].version : null
}

output "ravion_operator_agent_id" {
  description = "Ravion Operator record id (opagt_...) for this cluster (null if disabled). Stable across rotations — correlate agent logs by it."
  # A computed attribute of the credential resource, not secret material: the
  # client secret is the only sensitive attribute and is never output.
  value = var.ravion_operator_enabled ? ravion_operator_credential.this[0].operator_agent_id : null
}

output "ravion_operator_installation_id" {
  description = "Stable provider-neutral Operator installation ID, also exposed as ravion_operator_agent_id for compatibility."
  value       = var.ravion_operator_enabled ? ravion_operator_credential.this[0].operator_agent_id : null
}

output "ravion_operator_execution_image" {
  description = "Configured coordinator/executor image override: empty when the chart supplies its bundled digest, or null when Operator or Job mode is disabled."
  value       = var.ravion_operator_enabled && var.ravion_operator_execution_jobs_enabled ? var.ravion_operator_execution_image : null
}

output "ravion_operator_client_id" {
  description = "WorkOS M2M client id the agent authenticates as (null if disabled). Not a secret, and identical for every cluster in the organization — the shared application's client id."
  value       = var.ravion_operator_enabled ? ravion_operator_credential.this[0].client_id : null
}

output "ravion_operator_client_secret_id" {
  description = "WorkOS id of the secret issued to this cluster (null if disabled). Not the secret itself: it identifies which credential a connecting agent is presenting."
  value       = var.ravion_operator_enabled ? ravion_operator_credential.this[0].secret_id : null
}

output "ravion_operator_credential_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret mirroring the agent's credential (null if disabled). An operator recovery copy of what Terraform state holds — nothing reads it back."
  value       = var.ravion_operator_enabled ? aws_secretsmanager_secret.ravion_operator_credential[0].arn : null
}

################################################################################
# Workload metrics (Amazon Managed Prometheus)
################################################################################

output "amp_workspace_id" {
  description = "Amazon Managed Prometheus workspace the collector writes to (null if metrics are disabled). The created workspace, or the one passed as amp_workspace_id."
  value       = local.amp_workspace_id
}

output "amp_workspace_arn" {
  description = "ARN of the AMP workspace (null if metrics are disabled). What a query role or cross-account grant is scoped to."
  value       = local.amp_workspace_arn
}

output "amp_remote_write_endpoint" {
  description = "SigV4-signed remote-write URL the collector posts to (null if metrics are disabled)."
  value       = local.amp_remote_write_endpoint
}

output "amp_query_endpoint" {
  description = "Prometheus-compatible query base URL for the workspace (null if metrics are disabled). Use it as-is as a Grafana datasource URL; append /api/v1/query for the HTTP API."
  value       = local.amp_query_endpoint
}

output "amp_region" {
  description = "Region the AMP workspace lives in (null if metrics are disabled). May differ from the cluster's region when amp_region is set."
  value       = local.amp_enabled ? local.amp_region : null
}

output "metrics_namespace" {
  description = "Kubernetes namespace the metrics components are installed into (null if metrics are disabled)."
  value       = local.metrics_on ? local.metrics_namespace : null
}

output "amp_remote_write_role_arn" {
  description = "ARN of the collector's Pod Identity role, scoped to aps:RemoteWrite on this workspace alone (null if metrics are disabled)."
  value       = local.amp_enabled ? module.amp_remote_write_role[0].role_arn : null
}

output "otel_collector_chart_version" {
  description = "Installed version of the opentelemetry-collector Helm chart (null if metrics are disabled)."
  value       = local.otel_metrics_enabled ? helm_release.otel_collector[0].version : null
}

output "kube_state_metrics_chart_version" {
  description = "Installed version of the kube-state-metrics Helm chart (null if not installed)."
  value       = local.kube_state_metrics_install ? helm_release.kube_state_metrics[0].version : null
}

################################################################################
# Grafana read access
################################################################################

output "grafana_role_arn" {
  description = "ARN of the role Amazon Managed Grafana assumes to query the AMP workspace and read the Container Insights log groups (null if disabled)."
  value       = var.grafana_role_creation_enabled ? module.grafana_role[0].role_arn : null
}

################################################################################
# Workload logs (Loki on S3)
################################################################################

output "loki_endpoint" {
  description = "In-cluster base URL of Loki (null if logs are disabled). Reachable only from inside the cluster, by design — Ravion queries it through the Ravion Operator's tunnel, so this is the endpoint Ravion Operator's proxy allowlist names, not something to publish."
  value       = local.loki_endpoint
}

output "loki_namespace" {
  description = "Kubernetes namespace Loki and Alloy are installed into (null if logs are disabled)."
  value       = local.loki_enabled ? local.logs_namespace : null
}

output "loki_s3_bucket" {
  description = "S3 bucket holding the log chunks and index (null if logs are disabled). Created by this module unless loki_s3_bucket_name brought an existing one."
  value       = local.loki_bucket_name
}

output "loki_s3_bucket_arn" {
  description = "ARN of the log bucket (null if logs are disabled). What the Loki role is scoped to."
  value       = local.loki_bucket_arn
}

output "loki_role_arn" {
  description = "ARN of Loki's Pod Identity role, scoped to read, write, and delete on the log bucket alone (null if logs are disabled). Delete is what lets the compactor enforce retention."
  value       = local.loki_enabled ? module.loki_role[0].role_arn : null
}

output "log_retention_days" {
  description = "How long logs stay queryable (null if logs are disabled). Enforced by Loki's compactor; the bucket lifecycle rule sweeps a week later as a backstop."
  value       = local.loki_enabled ? local.loki_config.retention_days : null
}

output "loki_chart_version" {
  description = "Installed version of the grafana/loki Helm chart (null if logs are disabled)."
  value       = local.loki_enabled ? helm_release.loki[0].version : null
}

output "alloy_chart_version" {
  description = "Installed version of the grafana/alloy Helm chart (null if logs are disabled)."
  value       = local.alloy_enabled ? helm_release.alloy[0].version : null
}

################################################################################
# In-cluster Grafana
################################################################################

output "grafana_namespace" {
  description = "Kubernetes namespace the in-cluster Grafana is installed into (null if disabled)."
  value       = var.grafana_enabled ? local.grafana_namespace : null
}

output "grafana_service" {
  description = "In-cluster Grafana Service (null if disabled). No ingress is created: reach it with 'kubectl -n <namespace> port-forward svc/<service> 3000:80', or add an ingress through grafana_helm_values."
  value       = var.grafana_enabled ? local.grafana_release_name : null
}

output "grafana_amp_role_arn" {
  description = "ARN of the in-cluster Grafana's Pod Identity role for querying the AMP workspace (null when Grafana or metrics are disabled). Distinct from grafana_role_arn, which is for Amazon Managed Grafana reaching in from outside."
  value       = var.grafana_enabled && local.amp_enabled ? module.grafana_workspace_read_role[0].role_arn : null
}

################################################################################
# Observability providers
#
# The contract the service modules (rvn-eks-web / worker / cron) and the control
# plane read. Two rules hold across all of it:
#
#   * The *_rendering_providers lists are IN FALLBACK ORDER. A service module
#     lists one ui.logs / ui.metrics entry per element, in this order, each
#     guarded on membership; the dashboard reads the first that can answer.
#
#   * The *_external_links lists are the ship-only providers. href_prefix is a
#     base URL the caller completes with its own namespace/workload query.
################################################################################

output "logs_providers" {
  description = "Log destinations selected for this cluster, as given. Always a list - empty when logs are off, never null, because a service module reads null as 'these add-ons predate providers'."
  value       = tolist(local.logs_providers)
}

output "logs_rendering_providers" {
  description = "The selected log providers Ravion's Logs tab can read, in fallback order: loki, then cloudwatch. Empty when logs are off, or when only ship-only providers are selected — the tab then shows the 'Open in ...' actions alone."
  value       = tolist(local.logs_rendering_providers)
}

output "logs_cloudwatch_log_group" {
  description = "CloudWatch Logs group Ravion's own log pipeline writes to (null unless cloudwatch is in logs_providers). One stream per pod, named <namespace>/<pod>/<container>. Distinct from the add-on's /aws/containerinsights/<cluster>/application group."
  value       = local.cloudwatch_log_group_name
}

output "logs_external_links" {
  description = "One entry per ship-only log provider: { provider, name, href_prefix }. href_prefix ends exactly where a query value begins, so the service module appends its own encoded query and nothing else. Always a list, empty when there are none."
  value       = tolist(local.logs_external_links)
}

output "metrics_providers" {
  description = "Metric destinations selected for this cluster, as given. Always a list - empty when metrics are off, never null."
  value       = tolist(local.metrics_providers)
}

output "metrics_rendering_providers" {
  description = "The selected metric providers Ravion's Metrics tab can read, in fallback order: amp, then prometheus, then cloudwatch. Empty when metrics are off."
  value       = tolist(local.metrics_rendering_providers)
}

output "metrics_external_links" {
  description = "One entry per ship-only metrics provider: { provider, name, href_prefix }, on the same terms as logs_external_links. Always a list, empty when there are none."
  value       = tolist(local.metrics_external_links)
}

output "prometheus_endpoint" {
  description = "In-cluster Prometheus base URL (null unless prometheus is in metrics_providers). Reachable only from inside the cluster: Ravion queries it through Ravion Operator, the same way it queries Loki."
  value       = local.prometheus_endpoint
}

output "grafana_cloud_logs_query_url" {
  description = "Grafana Cloud Loki query base URL, derived from the push URL (null unless grafana_cloud is in logs_providers). Named in Ravion Operator's proxy allowlist so the dashboard can read it through the agent."
  value       = local.grafana_cloud_logs_query_url
}

output "grafana_cloud_metrics_query_url" {
  description = "Grafana Cloud Prometheus query base URL, derived from the remote-write URL (null unless grafana_cloud is in metrics_providers)."
  value       = local.grafana_cloud_metrics_query_url
}

output "observability_credentials_secret_name" {
  description = "Name of the Kubernetes Secret in Ravion Operator's namespace holding the credential the agent presents when proxying a query to an external store (null when there is none). Keys are username/password. This is the name the control plane carries as auth_secret — it never sees the value."
  value       = local.observability_credentials_secret_name
}

output "observability_proxy_credentials" {
  description = "Every proxy credential this module materialized: { endpointPrefix, secretName, kind }. observability_credentials_secret_name is the first of them; this is the full mapping for a cluster that renders from more than one external store."
  value       = local.ravion_operator_proxy_credentials
}

output "observability_namespace" {
  description = "Kubernetes namespace the collectors, the log store, and the materialized vendor credentials are installed into."
  value       = local.observability_namespace
}

output "otel_logs_collector_role_arn" {
  description = "ARN of the log collector's Pod Identity role (null unless a log provider authenticates with AWS credentials). Scoped to the Ravion log group and, for OpenSearch, to signing domain requests."
  value       = local.otel_logs_needs_aws ? module.otel_logs_collector_role[0].role_arn : null
}

output "logs_opensearch_role_arn" {
  description = "ARN of the role the collector signs OpenSearch requests with (null unless opensearch is in logs_providers). Map it in the domain's access policy or its fine-grained role mapping - that half of the grant lives on the domain, which this module does not manage."
  value       = local.logs_opensearch_enabled ? module.otel_logs_collector_role[0].role_arn : null
}

output "prometheus_chart_version" {
  description = "Installed version of the prometheus Helm chart (null unless the module installed an in-cluster Prometheus)."
  value       = local.prometheus_install ? helm_release.prometheus[0].version : null
}
