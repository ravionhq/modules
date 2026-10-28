################################################################################
# Grafana Mimir: the horizontally scalable in-cluster metrics store
################################################################################

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
  mock_data "aws_eks_addon_version" {
    defaults = { version = "v1.66.0-eksbuild.1" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/test-cluster-observability" }
  }
  mock_data "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:us-east-2:123456789012:cluster/test-cluster"
      endpoint              = "https://mock.eks.amazonaws.com"
      version               = "1.36"
      certificate_authority = [{ data = "bW9jay1jYQ==" }]
      vpc_config = [{
        vpc_id                    = "vpc-12345678"
        cluster_security_group_id = "sg-12345678"
        control_plane_egress_mode = ""
        endpoint_private_access   = true
        endpoint_public_access    = false
        public_access_cidrs       = []
        security_group_ids        = []
        subnet_ids                = []
      }]
    }
  }
}
mock_provider "helm" {}
mock_provider "ravion" {}

variables {
  cluster_name      = "test-cluster"
  region            = "us-east-2"
  karpenter_enabled = false
  eso_enabled       = false
  logs_providers    = []
}

run "mimir_is_opt_in" {
  command = plan

  assert {
    condition     = length(helm_release.mimir) == 0 && length(module.mimir_bucket) == 0 && length(aws_eks_pod_identity_association.mimir) == 0
    error_message = "Mimir must be installed only when metrics_providers selects it."
  }

  assert {
    condition     = output.mimir_endpoint == null && output.mimir_remote_write_endpoint == null
    error_message = "Mimir's endpoints must be null when it is not selected."
  }
}

run "mimir_runs_classic_on_s3_with_three_copies" {
  command = plan

  variables {
    metrics_providers = ["mimir"]
  }

  assert {
    condition     = helm_release.mimir[0].chart == "mimir-distributed" && helm_release.mimir[0].repository == "https://grafana.github.io/helm-charts" && helm_release.mimir[0].version == "6.2.0" && helm_release.mimir[0].namespace == "ravion-operator"
    error_message = "Mimir must install the pinned grafana/mimir-distributed chart into the observability namespace."
  }

  # Kafka would be one more stateful system every team has to run.
  assert {
    condition     = yamldecode(helm_release.mimir[0].values[0]).kafka.enabled == false && yamldecode(helm_release.mimir[0].values[0]).mimir.structuredConfig.ingest_storage.enabled == false && yamldecode(helm_release.mimir[0].values[0]).minio.enabled == false
    error_message = "Mimir must run the classic ingester architecture, without Kafka or the bundled MinIO."
  }

  assert {
    condition     = yamldecode(helm_release.mimir[0].values[0]).mimir.structuredConfig.ingester.ring.replication_factor == 3 && yamldecode(helm_release.mimir[0].values[0]).ingester.replicas == 3
    error_message = "Mimir must keep three copies of every sample on three ingesters."
  }

  assert {
    condition     = yamldecode(helm_release.mimir[0].values[0]).mimir.structuredConfig.multitenancy_enabled == false
    error_message = "One cluster is one tenant: writers and readers must not need a tenant header."
  }

  assert {
    condition = (
      yamldecode(helm_release.mimir[0].values[0]).mimir.structuredConfig.common.storage.backend == "s3" &&
      yamldecode(helm_release.mimir[0].values[0]).mimir.structuredConfig.common.storage.s3.region == "us-east-2" &&
      yamldecode(helm_release.mimir[0].values[0]).mimir.structuredConfig.common.storage.s3.endpoint == "s3.us-east-2.amazonaws.com" &&
      yamldecode(helm_release.mimir[0].values[0]).mimir.structuredConfig.blocks_storage.s3.bucket_name == "ravion-mimir-test-cluster-123456789012" &&
      yamldecode(helm_release.mimir[0].values[0]).mimir.structuredConfig.blocks_storage.storage_prefix == "blocks"
    )
    error_message = "Mimir must keep its blocks in its own S3 bucket in the cluster's region."
  }

  assert {
    condition     = !can(yamldecode(helm_release.mimir[0].values[0]).mimir.structuredConfig.common.storage.s3.access_key_id)
    error_message = "Mimir must reach S3 through Pod Identity, never with static keys."
  }

  assert {
    condition     = length(module.mimir_bucket) == 1 && output.mimir_s3_bucket == "ravion-mimir-test-cluster-123456789012"
    error_message = "Mimir must create its bucket when none is given."
  }

  assert {
    condition     = yamldecode(helm_release.mimir[0].values[0]).serviceAccount.name == "ravion-mimir" && aws_eks_pod_identity_association.mimir[0].service_account == "ravion-mimir" && aws_eks_pod_identity_association.mimir[0].namespace == "ravion-operator"
    error_message = "Every Mimir component must run as the one service account its Pod Identity association binds."
  }

  # 365 days, the same default history as Thanos.
  assert {
    condition     = yamldecode(helm_release.mimir[0].values[0]).mimir.structuredConfig.limits.compactor_blocks_retention_period == "8760h"
    error_message = "Mimir's compactor must own retention, 365 days by default."
  }

  assert {
    condition     = yamldecode(helm_release.mimir[0].values[0]).ruler.enabled == false && yamldecode(helm_release.mimir[0].values[0]).alertmanager.enabled == false && yamldecode(helm_release.mimir[0].values[0]).rollout_operator.enabled == false
    error_message = "Mimir must not run a ruler, Alertmanager or rollout-operator nothing uses."
  }
}

run "mimir_never_rejects_metrics" {
  command = plan

  variables {
    metrics_providers = ["mimir"]
  }

  # Mimir's own defaults cap a tenant at 150,000 series and 10,000 samples a
  # second; ravion-prod alone holds 118,000 series.
  assert {
    condition     = yamldecode(helm_release.mimir[0].values[0]).mimir.structuredConfig.limits.max_global_series_per_user == 0 && yamldecode(helm_release.mimir[0].values[0]).mimir.structuredConfig.limits.max_global_series_per_metric == 0
    error_message = "Mimir must not cap the number of series."
  }

  assert {
    condition     = yamldecode(helm_release.mimir[0].values[0]).mimir.structuredConfig.limits.ingestion_rate >= 10000000 && yamldecode(helm_release.mimir[0].values[0]).mimir.structuredConfig.limits.ingestion_burst_size >= yamldecode(helm_release.mimir[0].values[0]).mimir.structuredConfig.limits.ingestion_rate
    error_message = "Mimir's ingestion rate must be effectively unlimited."
  }

  # Collectors retry for up to ten minutes; their late samples must land.
  assert {
    condition     = yamldecode(helm_release.mimir[0].values[0]).mimir.structuredConfig.limits.out_of_order_time_window == "15m"
    error_message = "Mimir must accept samples a collector retried for up to ten minutes."
  }

  assert {
    condition     = yamldecode(helm_release.mimir[0].values[0]).mimir.structuredConfig.limits.max_label_names_per_series >= 100 && yamldecode(helm_release.mimir[0].values[0]).mimir.structuredConfig.limits.max_label_value_length >= 16384
    error_message = "Mimir must accept series with many and long labels."
  }
}

run "metrics_flow_into_mimir" {
  command = plan

  variables {
    metrics_providers = ["mimir"]
    traces_destinations = [{
      destination               = "tempo"
      metrics_generator_enabled = true
    }]
  }

  assert {
    condition     = output.mimir_remote_write_endpoint == "http://ravion-mimir-gateway.ravion-operator.svc.cluster.local/api/v1/push" && output.mimir_endpoint == "http://ravion-mimir-gateway.ravion-operator.svc.cluster.local/prometheus"
    error_message = "Mimir is written through its gateway's push path and read under /prometheus."
  }

  assert {
    condition     = yamldecode(helm_release.otel_collector[0].values[0]).config.exporters["prometheusremotewrite/mimir"].endpoint == "http://ravion-mimir-gateway.ravion-operator.svc.cluster.local/api/v1/push" && yamldecode(helm_release.otel_collector[0].values[0]).config.exporters["prometheusremotewrite/mimir"].retry_on_failure.max_elapsed_time == "600s"
    error_message = "The metrics collector must write every sample to Mimir and keep retrying across a restart."
  }

  assert {
    condition     = yamldecode(helm_release.otlp_collector[0].values[0]).config.service.pipelines.metrics.exporters == ["prometheusremotewrite/mimir"]
    error_message = "The OTLP collector must send application metrics to Mimir."
  }

  assert {
    condition     = [for target in yamldecode(helm_release.tempo[0].values[0]).tempo.metricsGenerator.storage.remote_write : target.url] == ["http://ravion-mimir-gateway.ravion-operator.svc.cluster.local/api/v1/push"]
    error_message = "Tempo's metrics generator must write to Mimir when it is the in-cluster store."
  }

  assert {
    condition     = one([for source in local.grafana_datasources : source if source.uid == "ravion-tempo"]).jsonData.serviceMap.datasourceUid == "ravion-mimir"
    error_message = "Grafana's service graph must read the store the generator writes to."
  }
}

run "ravion_reads_mimir" {
  command = plan

  variables {
    metrics_providers       = ["mimir"]
    grafana_enabled         = true
    ravion_operator_enabled = true
  }

  assert {
    condition     = output.metrics_rendering_providers == tolist(["mimir"]) && output.prometheus_endpoint == "http://ravion-mimir-gateway.ravion-operator.svc.cluster.local/prometheus"
    error_message = "With Mimir alone, Ravion's Metrics tab must query Mimir's Prometheus API."
  }

  assert {
    condition     = contains(yamldecode(local.ravion_operator_observability_proxy_values[0]).httpProxy.allowedEndpoints, "http://ravion-mimir-gateway.ravion-operator.svc.cluster.local/prometheus")
    error_message = "Ravion Operator must be allowed to proxy queries to Mimir."
  }

  assert {
    condition     = one([for source in local.grafana_datasources : source if source.uid == "ravion-mimir"]).url == "http://ravion-mimir-gateway.ravion-operator.svc.cluster.local/prometheus" && one([for source in local.grafana_datasources : source if source.uid == "ravion-mimir"]).isDefault
    error_message = "Grafana must read Mimir, as its default data source when nothing else is selected."
  }
}

run "prometheus_and_mimir_run_side_by_side" {
  command = plan

  variables {
    metrics_providers = ["prometheus", "mimir"]
  }

  assert {
    condition     = output.metrics_rendering_providers == tolist(["prometheus", "mimir"]) && output.prometheus_endpoint == "http://ravion-thanos-query.ravion-operator.svc.cluster.local:9090"
    error_message = "While moving to Mimir, Ravion keeps reading Prometheus first."
  }

  assert {
    condition     = contains(keys(yamldecode(helm_release.otel_collector[0].values[0]).config.exporters), "prometheusremotewrite/in_cluster") && contains(keys(yamldecode(helm_release.otel_collector[0].values[0]).config.exporters), "prometheusremotewrite/mimir")
    error_message = "Both stores must receive every sample during a move."
  }

  assert {
    condition     = length(helm_release.prometheus) == 1 && length(helm_release.mimir) == 1
    error_message = "Selecting both installs both."
  }
}

run "an_existing_bucket_and_retention" {
  command = plan

  variables {
    metrics_providers = ["mimir"]
    metrics_mimir = {
      retention_days = 30
      s3_bucket_name = "acme-mimir-blocks"
    }
  }

  assert {
    condition     = length(module.mimir_bucket) == 0 && yamldecode(helm_release.mimir[0].values[0]).mimir.structuredConfig.blocks_storage.s3.bucket_name == "acme-mimir-blocks" && output.mimir_s3_bucket == "acme-mimir-blocks"
    error_message = "A given bucket must be used, not created."
  }

  assert {
    condition     = yamldecode(helm_release.mimir[0].values[0]).mimir.structuredConfig.limits.compactor_blocks_retention_period == "720h"
    error_message = "retention_days must set the compactor's retention."
  }
}

run "zone_aware_replication_keeps_a_copy_in_every_zone" {
  command = plan

  variables {
    metrics_providers = ["mimir"]
    metrics_mimir = {
      zones = ["us-east-2a", "us-east-2b", "us-east-2c"]
    }
  }

  assert {
    condition     = yamldecode(helm_release.mimir[0].values[0]).ingester.zoneAwareReplication.enabled && yamldecode(helm_release.mimir[0].values[0]).store_gateway.zoneAwareReplication.enabled && yamldecode(helm_release.mimir[0].values[0]).rollout_operator.enabled
    error_message = "Zones turn on zone-aware replication for ingesters and store-gateways, with the rollout-operator that drives their rollouts."
  }

  assert {
    condition     = [for zone in yamldecode(helm_release.mimir[0].values[0]).ingester.zoneAwareReplication.zones : zone.nodeSelector["topology.kubernetes.io/zone"]] == ["us-east-2a", "us-east-2b", "us-east-2c"] && [for zone in yamldecode(helm_release.mimir[0].values[0]).ingester.zoneAwareReplication.zones : zone.name] == ["zone-a", "zone-b", "zone-c"]
    error_message = "Each Mimir zone must pin its pods to one availability zone."
  }

  assert {
    condition     = alltrue([for zone in yamldecode(helm_release.mimir[0].values[0]).ingester.zoneAwareReplication.zones : zone.extraAffinity == local.addon_store_placement.affinity]) && yamldecode(helm_release.mimir[0].values[0]).ingester.zoneAwareReplication.topologyKey == "kubernetes.io/hostname"
    error_message = "Zoned ingesters ignore the component affinity: each zone must carry the store placement, and copies in different zones must not share a node."
  }
}

run "rejects_fewer_than_three_zones" {
  command = plan

  variables {
    metrics_providers = ["mimir"]
    metrics_mimir = {
      zones = ["us-east-2a", "us-east-2b"]
    }
  }

  expect_failures = [var.metrics_mimir]
}

run "rejects_an_invalid_bucket_name" {
  command = plan

  variables {
    metrics_providers = ["mimir"]
    metrics_mimir = {
      s3_bucket_name = "Not_A_Bucket"
    }
  }

  expect_failures = [var.metrics_mimir]
}

run "mimir_and_thanos_cannot_share_a_bucket" {
  command = plan

  variables {
    metrics_providers = ["prometheus", "mimir"]
    metrics_prometheus = {
      s3_bucket_name = "shared-metrics"
    }
    metrics_mimir = {
      s3_bucket_name = "shared-metrics"
    }
  }

  expect_failures = [helm_release.mimir]
}

# A hostname spread alone let ravion-prod run two of three ingesters on one
# node: with two nodes up, 2 and 1 is within a skew of one.
run "ingesters_and_store_gateways_never_share_a_node" {
  command = plan

  variables {
    metrics_providers = ["mimir"]
  }

  assert {
    condition = alltrue([
      for component, label in { ingester = "ingester", store_gateway = "store-gateway" } :
      one(yamldecode(helm_release.mimir[0].values[0])[component].affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution).topologyKey == "kubernetes.io/hostname" &&
      one(yamldecode(helm_release.mimir[0].values[0])[component].affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution).labelSelector.matchLabels == {
        "app.kubernetes.io/component" = label
        "app.kubernetes.io/instance"  = "ravion-mimir"
        "app.kubernetes.io/name"      = "mimir"
      }
    ])
    error_message = "Ingesters and store-gateways must refuse to share a node with another replica of their own component."
  }

  # Helm deep-merges value files, so the store placement's node affinity
  # joins the anti-affinity instead of replacing it.
  assert {
    condition     = can(yamldecode(helm_release.mimir[0].values[2]).ingester.affinity.nodeAffinity) && !can(yamldecode(helm_release.mimir[0].values[2]).ingester.affinity.podAntiAffinity)
    error_message = "The store placement document must carry only node affinity, leaving the anti-affinity in place."
  }
}

run "zoned_replicas_keep_their_own_affinity" {
  command = plan

  variables {
    metrics_providers = ["mimir"]
    metrics_mimir = {
      zones = ["us-east-2a", "us-east-2b", "us-east-2c"]
    }
  }

  assert {
    condition     = !can(yamldecode(helm_release.mimir[0].values[0]).ingester.affinity) && !can(yamldecode(helm_release.mimir[0].values[0]).store_gateway.affinity)
    error_message = "Zoned ingesters ignore the component affinity; the anti-affinity must not be set there."
  }
}

run "churn_compacts_the_head_early" {
  command = plan

  variables {
    metrics_providers = ["mimir"]
  }

  # 6Gi: half of it at 8KiB a series.
  assert {
    condition     = yamldecode(helm_release.mimir[0].values[0]).mimir.structuredConfig.blocks_storage.tsdb.early_head_compaction_min_in_memory_series == 393216
    error_message = "The default 6Gi ingester must compact early past 393,216 in-memory series."
  }
}

run "early_compaction_follows_the_ingester_memory" {
  command = plan

  variables {
    metrics_providers = ["mimir"]
    mimir_ingester_resources = {
      requests = { cpu = "2", memory = "12Gi" }
      limits   = { memory = "12Gi" }
    }
  }

  assert {
    condition     = yamldecode(helm_release.mimir[0].values[0]).mimir.structuredConfig.blocks_storage.tsdb.early_head_compaction_min_in_memory_series == 786432
    error_message = "A 12Gi ingester must compact early past 786,432 in-memory series."
  }
}

run "early_compaction_is_off_for_an_unparsed_memory_limit" {
  command = plan

  variables {
    metrics_providers = ["mimir"]
    mimir_ingester_resources = {
      requests = { cpu = "2", memory = "12G" }
      limits   = { memory = "12G" }
    }
  }

  assert {
    condition     = yamldecode(helm_release.mimir[0].values[0]).mimir.structuredConfig.blocks_storage.tsdb.early_head_compaction_min_in_memory_series == 0
    error_message = "A memory limit the module cannot read must leave early compaction off rather than guess."
  }
}

# Without resilience the module does not apply mimir_ingester_resources, so a
# threshold derived from it would follow a limit no pod has.
run "early_compaction_needs_the_limit_the_module_applies" {
  command = plan

  variables {
    metrics_providers        = ["mimir"]
    addon_resilience_enabled = false
  }

  assert {
    condition     = yamldecode(helm_release.mimir[0].values[0]).mimir.structuredConfig.blocks_storage.tsdb.early_head_compaction_min_in_memory_series == 0
    error_message = "Early compaction must stay off when the module does not set the ingesters' memory limit."
  }
}

run "ingesters_get_a_go_memory_limit_and_store_gateways_room_for_their_heap" {
  command = plan

  variables {
    metrics_providers = ["mimir"]
  }

  # 90% of the 6Gi limit, in MiB.
  assert {
    condition     = one([for d in helm_release.mimir[0].values : yamldecode(d).ingester if can(yamldecode(d).ingester.resources)]).env == [{ name = "GOMEMLIMIT", value = "5529MiB" }]
    error_message = "Ingesters must get GOMEMLIMIT at 90% of their memory limit."
  }

  # The chart sets the store-gateways' GOMEMLIMIT to their memory request.
  assert {
    condition     = one([for d in helm_release.mimir[0].values : yamldecode(d).store_gateway if can(yamldecode(d).store_gateway.resources)]).resources == { requests = { cpu = "500m", memory = "2Gi" }, limits = { memory = "3Gi" } }
    error_message = "Store-gateways must request 2Gi, above the heap they hold while serving queries."
  }

  assert {
    condition     = yamldecode(helm_release.mimir[0].values[0]).ingester.replicas == 3 && !can(yamldecode(helm_release.mimir[0].values[0]).mimir.structuredConfig.ingester.instance_limits)
    error_message = "By default three ingesters run with no series limit."
  }
}

run "ingester_count_size_and_series_limit_are_configurable" {
  command = plan

  variables {
    metrics_providers         = ["mimir"]
    mimir_ingester_replicas   = 6
    mimir_ingester_max_series = 3500000
    mimir_ingester_resources = {
      requests = { cpu = "1", memory = "12Gi" }
      limits   = { memory = "12Gi" }
    }
  }

  assert {
    condition     = yamldecode(helm_release.mimir[0].values[0]).ingester.replicas == 6
    error_message = "mimir_ingester_replicas must set the ingester count."
  }

  assert {
    condition     = yamldecode(helm_release.mimir[0].values[0]).mimir.structuredConfig.ingester.instance_limits.max_series == 3500000 && yamldecode(helm_release.mimir[0].values[0]).mimir.structuredConfig.ingester.ring.replication_factor == 3
    error_message = "mimir_ingester_max_series must reach the ingester's instance limits, beside its ring."
  }

  assert {
    condition     = one([for d in helm_release.mimir[0].values : yamldecode(d).ingester if can(yamldecode(d).ingester.resources)]).env == [{ name = "GOMEMLIMIT", value = "11059MiB" }] && yamldecode(helm_release.mimir[0].values[0]).mimir.structuredConfig.blocks_storage.tsdb.early_head_compaction_min_in_memory_series == 786432
    error_message = "GOMEMLIMIT and the early compaction threshold must follow a 12Gi limit."
  }
}

run "rejects_fewer_than_three_ingesters" {
  command = plan

  variables {
    metrics_providers       = ["mimir"]
    mimir_ingester_replicas = 2
  }

  expect_failures = [var.mimir_ingester_replicas]
}

run "ingester_go_memory_limit_follows_a_limit_set_in_chart_values" {
  command = plan

  variables {
    metrics_providers = ["mimir"]
    mimir_helm_values = ["ingester:\n  resources:\n    limits:\n      memory: 12Gi\n"]
  }

  assert {
    condition     = one([for d in helm_release.mimir[0].values : yamldecode(d).ingester if can(yamldecode(d).ingester.env)]).env == [{ name = "GOMEMLIMIT", value = "11059MiB" }]
    error_message = "Ingester GOMEMLIMIT must follow the memory limit mimir_helm_values sets"
  }
}
