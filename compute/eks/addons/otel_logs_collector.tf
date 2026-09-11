################################################################################
# OpenTelemetry log collector — every destination Alloy cannot speak to
#
# A DaemonSet that tails /var/log/pods on its own node and ships each line to
# every non-Loki log provider the user selected: CloudWatch Logs, Datadog, New
# Relic, a custom OTLP endpoint. It is only installed when at least one of those
# is selected — a default cluster (logs_providers = [loki]) runs Alloy alone.
#
# Four things about the shape of this file:
#
#   1. TWO COLLECTORS, NOT SEVEN AGENTS. Alloy carries the loki-family
#      destinations because Ravion's log views are written against its label
#      contract; this one carries the rest. Both fan out, so several vendors are
#      several exporters on one pipeline rather than several DaemonSets.
#
#   2. THE CONTRIB IMAGE, NOT THE AWS DISTRO. The AWS Distro does not ship the
#      datadog or awscloudwatchlogs exporters, so this collector always runs the
#      upstream contrib distribution. It is pinned; moving it is a module
#      change, not whatever the registry called latest that day.
#
#   3. IT READS FILES, NOT THE API. Same trade as Alloy: a host mount and a root
#      container, in exchange for keeping the read load of every container in
#      the cluster off the API server. The only API access is k8sattributes
#      resolving a pod's workload, which is a watch on pods and replicasets.
#
#   4. CLOUDWATCH STREAMS ARE PER POD. The exporter names the group statically
#      and takes the stream from a resource attribute, which the transform
#      processor sets to <namespace>/<pod>/<container> — the shape the service
#      modules' stream prefix filter expects.
################################################################################

locals {
  otel_logs_collector_name = "ravion-otel-logs-collector"

  otel_logs_resource_limits = merge(
    var.otel_logs_collector_resources.cpu_limit == null ? {} : { cpu = var.otel_logs_collector_resources.cpu_limit },
    var.otel_logs_collector_resources.memory_limit == null ? {} : { memory = var.otel_logs_collector_resources.memory_limit },
  )

  otel_logs_resource_requests = merge(
    var.otel_logs_collector_resources.cpu_request == null ? {} : { cpu = var.otel_logs_collector_resources.cpu_request },
    var.otel_logs_collector_resources.memory_request == null ? {} : { memory = var.otel_logs_collector_resources.memory_request },
  )

  otel_logs_resources = merge(
    length(local.otel_logs_resource_requests) > 0 ? { requests = local.otel_logs_resource_requests } : {},
    length(local.otel_logs_resource_limits) > 0 ? { limits = local.otel_logs_resource_limits } : {},
  )

  # The pod log path is /var/log/pods/<namespace>_<pod>_<uid>/<container>/N.log,
  # so an excluded namespace is a glob. The collector's own container is
  # excluded unconditionally: shipping a shipper's logs about shipping is how a
  # feedback loop starts.
  otel_logs_exclude_paths = concat(
    [for namespace in var.logs_excluded_namespaces : "/var/log/pods/${namespace}_*/*/*.log"],
    ["/var/log/pods/*/${local.otel_logs_collector_name}/*.log"],
    ["/var/log/pods/*/otc-container/*.log"],
  )

  # Resource attributes every exporter downstream reads. `workload` collapses
  # the controller kinds into one name, which is what the dashboard filters on.
  otel_logs_resource_statements = concat(
    [
      "set(attributes[\"k8s.workload.name\"], attributes[\"k8s.deployment.name\"]) where attributes[\"k8s.deployment.name\"] != nil",
      "set(attributes[\"k8s.workload.name\"], attributes[\"k8s.statefulset.name\"]) where attributes[\"k8s.workload.name\"] == nil and attributes[\"k8s.statefulset.name\"] != nil",
      "set(attributes[\"k8s.workload.name\"], attributes[\"k8s.daemonset.name\"]) where attributes[\"k8s.workload.name\"] == nil and attributes[\"k8s.daemonset.name\"] != nil",
      "set(attributes[\"k8s.workload.name\"], attributes[\"k8s.cronjob.name\"]) where attributes[\"k8s.workload.name\"] == nil and attributes[\"k8s.cronjob.name\"] != nil",
      "set(attributes[\"k8s.workload.name\"], attributes[\"k8s.job.name\"]) where attributes[\"k8s.workload.name\"] == nil and attributes[\"k8s.job.name\"] != nil",
      "set(attributes[\"k8s.workload.name\"], attributes[\"k8s.pod.name\"]) where attributes[\"k8s.workload.name\"] == nil",
      "set(attributes[\"k8s.cluster.name\"], \"${var.cluster_name}\")",
    ],
    # CHART/EXPORTER CONTRACT, VERIFY ON UPGRADE: the awscloudwatchlogs exporter
    # prefers the group and stream named in these resource attributes over its
    # own static configuration. The static log_group_name below is set to the
    # same value, so a version that ignores the attributes still writes to the
    # right group — only the per-pod stream naming would be lost.
    local.logs_cloudwatch_enabled ? [
      "set(attributes[\"aws.log.group.names\"], \"${local.cloudwatch_logs_config.log_group_name}\")",
      "set(attributes[\"aws.log.stream.names\"], Concat([attributes[\"k8s.namespace.name\"], attributes[\"k8s.pod.name\"], attributes[\"k8s.container.name\"]], \"/\"))",
    ] : [],
  )

  otel_logs_exporters = merge(
    { debug = null },
    local.logs_cloudwatch_enabled ? {
      awscloudwatchlogs = {
        region = local.observability_region
        # Named here as well as on the resource attributes, so a collector that
        # ignores the attributes still lands in the right group.
        log_group_name  = local.cloudwatch_logs_config.log_group_name
        log_stream_name = "otel"
        log_retention   = local.cloudwatch_logs_config.retention_days
        # The application's own line, not an OTLP envelope around it: this group
        # is read by Ravion's CloudWatch log source and by Logs Insights, both
        # of which expect the log as the application wrote it.
        raw_log = true
      }
    } : {},
    local.logs_datadog_enabled ? {
      datadog = {
        api = {
          site = local.datadog_config.site
          key  = "$${env:DATADOG_API_KEY}"
        }
      }
    } : {},
    local.logs_new_relic_enabled ? {
      "otlphttp/new_relic" = {
        endpoint = local.new_relic_otlp_endpoint
        headers = {
          "api-key" = "$${env:NEW_RELIC_LICENSE_KEY}"
        }
      }
    } : {},
    local.logs_opensearch_enabled ? {
      # The exporter signs with the collector's Pod Identity credentials through
      # the sigv4auth extension; the domain has to map logs_opensearch_role_arn
      # in its access policy or its fine-grained role mapping.
      opensearch = {
        http = {
          endpoint = local.opensearch_config.endpoint
          auth = {
            authenticator = "sigv4auth/opensearch"
          }
        }
        logs_index = local.opensearch_config.index_prefix
      }
    } : {},
    local.logs_splunk_enabled ? {
      splunk_hec = merge(
        {
          endpoint = local.splunk_config.hec_url
          token    = "$${env:SPLUNK_HEC_TOKEN}"
          source   = "kubernetes"
        },
        local.splunk_config.index == null ? {} : { index = local.splunk_config.index },
      )
    } : {},
    local.logs_otlp_enabled ? {
      "otlphttp/custom" = merge(
        { endpoint = local.otlp_logs_config.endpoint },
        local.otlp_logs_config.headers_secret_arn == null ? {} : {
          headers = { authorization = "$${env:OTLP_LOGS_AUTHORIZATION}" }
        },
      )
    } : {},
  )

  # CloudWatch signs with the Pod Identity credentials the AWS SDK resolves and
  # needs no extension; OpenSearch's exporter asks for a named signer.
  otel_logs_extensions = local.logs_opensearch_enabled ? {
    "sigv4auth/opensearch" = {
      region = local.observability_region
      # "es" for a managed domain; a Serverless collection would be "aoss".
      service = "es"
    }
  } : {}

  otel_logs_pipeline_exporters = [for name, _ in local.otel_logs_exporters : name if name != "debug"]

  otel_logs_extra_envs = [
    for secret in local.otel_logs_secret_env : {
      name = secret.environment
      valueFrom = {
        secretKeyRef = {
          name = secret.name
          key  = secret.secret_key
        }
      }
    }
  ]

  # The only log destinations that authenticate with AWS credentials rather
  # than a token.
  otel_logs_needs_aws = local.logs_cloudwatch_enabled || local.logs_opensearch_enabled

  otel_logs_values = local.otel_logs_enabled ? templatefile("${path.module}/templates/otel_logs_values.yaml.tpl", {
    name             = local.otel_logs_collector_name
    image_repository = var.otel_contrib_image_repository
    image_tag        = var.otel_contrib_image_tag
    command_name     = var.otel_contrib_command_name
    service_account  = var.otel_logs_collector_service_account
    resources        = local.otel_logs_resources
    extra_envs       = local.otel_logs_extra_envs

    exclude_paths       = local.otel_logs_exclude_paths
    resource_statements = local.otel_logs_resource_statements

    exporters          = local.otel_logs_exporters
    extensions         = local.otel_logs_extensions
    service_extensions = concat(["health_check"], sort(keys(local.otel_logs_extensions)))
    pipeline_exporters = sort(local.otel_logs_pipeline_exporters)
  }) : null
}

################################################################################
# CloudWatch Logs write identity
#
# Only the log group this module owns. CreateLogGroup is here because the
# exporter creates the group on first write and sets its retention; describing
# groups cannot be scoped to one, which is the one wildcard below.
################################################################################

data "aws_iam_policy_document" "otel_logs_cloudwatch" {
  count = local.otel_logs_needs_aws ? 1 : 0

  dynamic "statement" {
    for_each = local.logs_opensearch_enabled && local.opensearch_config.endpoint != null ? [1] : []

    content {
      sid    = "WriteOpenSearchIndexes"
      effect = "Allow"
      actions = [
        "es:ESHttpPost",
        "es:ESHttpPut",
        "es:ESHttpHead",
        "es:ESHttpGet",
      ]
      # Every domain in the account: the endpoint is a URL, not an ARN, and
      # resolving one to the other would need a data source (and a domain that
      # already exists at plan time). The domain's own access policy is the
      # second half of this grant and is where it gets narrowed.
      resources = ["arn:${data.aws_partition.current.partition}:es:${local.observability_region}:${data.aws_caller_identity.current.account_id}:domain/*"]
    }
  }

  dynamic "statement" {
    for_each = local.logs_cloudwatch_enabled ? [1] : []

    content {
      sid    = "WriteRavionLogGroup"
      effect = "Allow"
      actions = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:PutRetentionPolicy",
        "logs:DescribeLogStreams",
      ]
      resources = [
        "arn:${data.aws_partition.current.partition}:logs:${local.observability_region}:${data.aws_caller_identity.current.account_id}:log-group:${local.cloudwatch_logs_config.log_group_name}",
        "arn:${data.aws_partition.current.partition}:logs:${local.observability_region}:${data.aws_caller_identity.current.account_id}:log-group:${local.cloudwatch_logs_config.log_group_name}:*",
      ]
    }
  }

  dynamic "statement" {
    for_each = local.logs_cloudwatch_enabled ? [1] : []

    content {
      sid       = "DescribeLogGroups"
      effect    = "Allow"
      actions   = ["logs:DescribeLogGroups"]
      resources = ["*"]
    }
  }
}

module "otel_logs_collector_role" {
  count = local.otel_logs_needs_aws ? 1 : 0

  source = "../../../security/iam"

  name        = "${var.cluster_name}-otel-logs-collector"
  description = "Log collector Pod Identity role for ${var.cluster_name}"

  custom_assume_role_policy = local.pod_identity_trust_policy

  inline_policies = {
    "log-destination-write" = data.aws_iam_policy_document.otel_logs_cloudwatch[0].json
  }

  tags = local.tags
}

resource "aws_eks_pod_identity_association" "otel_logs_collector" {
  count = local.otel_logs_needs_aws ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = local.logs_namespace
  service_account = var.otel_logs_collector_service_account
  role_arn        = module.otel_logs_collector_role[0].role_arn

  tags = local.tags
}

################################################################################
# The collector
################################################################################

resource "helm_release" "otel_logs_collector" {
  count = local.otel_logs_enabled ? 1 : 0

  name       = local.otel_logs_collector_name
  namespace  = local.logs_namespace
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  version    = var.otel_collector_chart_version

  create_namespace = true
  upgrade_install  = true

  values = concat([local.otel_logs_values], var.otel_logs_collector_helm_values)

  depends_on = [
    helm_release.lb_controller,
    aws_eks_pod_identity_association.otel_logs_collector,
    helm_release.observability_secrets,
  ]

  lifecycle {
    precondition {
      condition     = !local.logs_datadog_enabled || local.datadog_config.api_key_secret_arn != null
      error_message = "datadog is in logs_providers but no API key secret ARN was given. The key is read in-cluster from Secrets Manager by External Secrets; without an ARN the collector has nothing to authenticate with."
    }

    precondition {
      condition     = !local.logs_new_relic_enabled || local.new_relic_config.license_key_secret_arn != null
      error_message = "new_relic is in logs_providers but no license key secret ARN was given. The key is read in-cluster from Secrets Manager by External Secrets."
    }

    precondition {
      condition     = !local.logs_otlp_enabled || local.otlp_logs_config.endpoint != null
      error_message = "otlp is in logs_providers but no OTLP endpoint was given. There is nowhere to send the logs."
    }

    precondition {
      condition     = !local.logs_opensearch_enabled || local.opensearch_config.endpoint != null
      error_message = "opensearch is in logs_providers but no domain endpoint was given. Also map logs_opensearch_role_arn into the domain's access policy or fine-grained role mapping: the collector signs with that role, and OpenSearch is the only half of the grant this module cannot write."
    }

    precondition {
      condition     = !local.logs_splunk_enabled || (local.splunk_config.hec_url != null && local.splunk_config.hec_token_secret_arn != null)
      error_message = "splunk is in logs_providers but its HEC URL or token secret ARN is missing. Both are required: the token is read in-cluster from Secrets Manager by External Secrets."
    }
  }
}
