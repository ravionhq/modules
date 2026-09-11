import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { join, resolve } from "node:path";
import { compileAllDefinitions, CompileError, compileDefinitionFile } from "../src/compiler.js";

const fixturesDir = join(process.cwd(), "test", "fixtures", "compile");
const repoRoot = resolve(process.cwd(), "../..");

describe("compiler", () => {
  it("compiles one definition file to canonical module config", async () => {
    const compiled = await compileDefinitionFile(join(fixturesDir, "modules", "networking", "vpc", "ravion-aws-vpc-definition.yml"));

    assert.equal(compiled.published, true);
    assert.equal(compiled.global, undefined);
    assert.equal(compiled.type, "ravion-aws-vpc");
    assert.equal(compiled.name, "AWS VPC");
    assert.equal(compiled.description, "AWS VPC and subnets");
    assert.equal(compiled.version, "1.2.3");
    assert.equal(compiled.releaseDescription, "Add subnet options.");
    assert.deepEqual(compiled.module, {
      inputs: [
        { id: "name", type: "string", label: "Name", required: true },
        { id: "environment", type: "string", label: "Environment", required: true },
        { id: "networking", type: "section", label: "Networking" },
        {
          id: "vpc",
          type: "stack",
          label: "VPC",
          outputs: {
            vpc_id: "VPC ID",
          },
        },
        {
          id: "advanced",
          type: "object",
          label: "Advanced",
          properties: {
            enabled: { type: "boolean", default: true },
          },
        },
      ],
      stack: {
        pipelines: {
          defaults: {
            variant: "standard",
            input: {
              source: {
                repo: "https://github.com/ravionhq/modules",
                ref: "ravion-aws-vpc@1.2.3",
                base_path: "networking/vpc",
              },
            },
          },
          change: { pipeline_id: "terraform-change" },
        },
        ravion_state_backend_workspace: "<< module.given_id >>",
        type: "opentofu",
        source: {
          repo: "https://github.com/ravionhq/modules",
          ref: "ravion-aws-vpc@1.2.3",
          base_path: "networking/vpc",
        },
      },
      deploy: {
        strategy: "rolling",
      },
      readme: "Terraform source https://github.com/ravionhq/modules/tree/ravion-aws-vpc@1.2.3/networking/vpc",
      settings: {
        advanced: {
          retries: 2,
        },
      },
    });
  });

  it("preserves a publication opt-out outside the canonical module config", async () => {
    const compiled = await compileDefinitionFile(join(process.cwd(), "test", "fixtures", "disabled-definition.yml"));

    assert.equal(compiled.published, false);
    assert.equal("published" in compiled.module, false);
  });

  it("preserves a global publication opt-out outside the canonical module config", async () => {
    const compiled = await compileDefinitionFile(join(process.cwd(), "test", "fixtures", "disabled-definition.yml"));

    assert.equal(compiled.global, false);
    assert.equal("global" in compiled.module, false);
  });

  it("compiles EKS cron scheduling controls and keeps the definition unpublished", async () => {
    const compiled = await compileDefinitionFile(join(repoRoot, "compute", "eks_service", "rvn-eks-cron-definition.yml"));
    const inputs = getModuleInputs(compiled.module);
    const deploy = assertRecord(compiled.module.deploy, "module.deploy");
    const definition = assertRecord(deploy.definition, "module.deploy.definition");
    const values = assertRecord(definition.values, "module.deploy.definition.values");

    assert.equal(compiled.published, false);
    assert.equal(findInput(inputs, "scheduling_enabled").default, true);
    assert.equal(inputs.some((input) => input.id === "suspend"), false);
    assert.equal(
      values.suspend,
      "<< module.input.scheduling_enabled != nil ? !module.input.scheduling_enabled : false >>",
    );
  });

  it("keeps the EKS cluster definition private", async () => {
    const compiled = await compileDefinitionFile(join(repoRoot, "compute", "eks", "rvn-eks-cluster-definition.yml"));

    assert.equal(compiled.global, false);
  });

  it("compiles all colocated definitions under module category directories", async () => {
    const compiled = await compileAllDefinitions(join(fixturesDir, "modules"));

    assert.deepEqual(compiled.map((definition) => definition.type), ["ravion-aws-cluster", "ravion-aws-vpc"]);
  });

  it("compiles the RDS storage alarm threshold with a fallback when the input is hidden", async () => {
    const compiled = await compileDefinitionFile(join(repoRoot, "database", "rds", "rvn-rds-definition.yml"));

    assert.equal(
      getTerraformVariable(compiled.module, "cloudwatch_alarm_storage_threshold"),
      "<< module.input.cloudwatch_alarm_storage_threshold_gib != null ? int(module.input.cloudwatch_alarm_storage_threshold_gib * 1073741824) : 5368709120 >>",
    );
  });

  it("compiles the Aurora memory alarm threshold with a fallback when the input is hidden", async () => {
    const compiled = await compileDefinitionFile(join(repoRoot, "database", "aurora", "rvn-aurora-definition.yml"));

    assert.equal(
      getTerraformVariable(compiled.module, "cloudwatch_alarm_memory_threshold"),
      "<< module.input.cloudwatch_alarm_memory_threshold_mib != null ? int(module.input.cloudwatch_alarm_memory_threshold_mib * 1048576) : 268435456 >>",
    );
  });

  it("compiles database password preservation with a false fallback when the input is hidden", async () => {
    const rds = await compileDefinitionFile(join(repoRoot, "database", "rds", "rvn-rds-definition.yml"));
    const aurora = await compileDefinitionFile(join(repoRoot, "database", "aurora", "rvn-aurora-definition.yml"));

    assert.equal(
      getTerraformVariable(rds.module, "master_user_password_preservation_enabled"),
      "<< module.input.master_user_password_preservation_enabled || false >>",
    );
    assert.equal(
      getTerraformVariable(aurora.module, "master_user_password_preservation_enabled"),
      "<< module.input.master_user_password_preservation_enabled || false >>",
    );
  });

  it("prevents EKS and database major version downgrades", async () => {
    const eks = await compileDefinitionFile(join(repoRoot, "compute", "eks", "rvn-eks-cluster-definition.yml"));
    const rds = await compileDefinitionFile(join(repoRoot, "database", "rds", "rvn-rds-definition.yml"));
    const aurora = await compileDefinitionFile(join(repoRoot, "database", "aurora", "rvn-aurora-definition.yml"));

    assert.equal(findInput(getModuleInputs(eks.module), "kubernetes_version").min_current_value, true);

    const rdsMajorVersion = findInput(getModuleInputs(rds.module), "engine_major_version");
    assert.equal(rdsMajorVersion.min_current_value, true);
    assert.equal(rdsMajorVersion.immutable, undefined);

    assert.equal(findInput(getModuleInputs(aurora.module), "engine_major_version").min_current_value, true);
  });

  it("compiles EKS web startup and recovery probes with safe path and timeout fallbacks", async () => {
    const compiled = await compileDefinitionFile(join(repoRoot, "compute", "eks_service", "rvn-eks-web-definition.yml"));
    const inputs = getModuleInputs(compiled.module);
    const deploy = assertRecord(compiled.module.deploy, "module.deploy");
    const definition = assertRecord(deploy.definition, "module.deploy.definition");
    const values = assertRecord(definition.values, "module.deploy.definition.values");
    const probes = assertRecord(values.probes, "module.deploy.definition.values.probes");
    const readiness = assertRecord(probes.readiness, "probes.readiness");
    const liveness = assertRecord(probes.liveness, "probes.liveness");
    const startup = assertRecord(probes.startup, "probes.startup");

    assert.equal(readiness.enabled, true);
    assert.equal(liveness.path, "<< module.input.liveness_probe_path || module.input.health_check_path >>");
    assert.equal(
      startup.path,
      "<< module.input.startup_probe_path || module.input.liveness_probe_path || module.input.health_check_path >>",
    );
    assert.equal(
      startup.failureThreshold,
      "<< module.input.startup_timeout_seconds != nil ? int((module.input.startup_timeout_seconds + 4) / 5) : 30 >>",
    );
    assert.equal(
      inputs.findIndex((input) => input.id === "probe_initial_delay_seconds"),
      inputs.findIndex((input) => input.id === "health_check_timeout") + 1,
    );
    assert.equal(inputs.some((input) => input.id === "section_load_balancer"), false);
    assert.equal(inputs.some((input) => input.id === "public_web_service_enabled"), false);
    assert.equal(inputs.some((input) => input.id === "healthy_threshold"), false);
    assert.equal(inputs.some((input) => input.id === "unhealthy_threshold"), false);
  });

  it("compiles EKS capacity forms and workload placement with safe defaults", async () => {
    const cluster = await compileDefinitionFile(join(repoRoot, "compute", "eks", "rvn-eks-cluster-definition.yml"));
    const addons = await compileDefinitionFile(join(repoRoot, "compute", "eks", "addons", "rvn-eks-addons-definition.yml"));
    const web = await compileDefinitionFile(join(repoRoot, "compute", "eks_service", "rvn-eks-web-definition.yml"));
    const clusterInputs = getModuleInputs(cluster.module);

    const additionalNodeGroups = findInput(clusterInputs, "node_groups");
    assert.equal(additionalNodeGroups.type, "object_map");
    const additionalNodeGroupInputs = additionalNodeGroups.item_inputs;
    assert.ok(Array.isArray(additionalNodeGroupInputs));
    const additionalNodeGroupFields = additionalNodeGroupInputs.map((input) =>
      assertRecord(input, "node_groups.item_inputs[]"),
    );
    assert.equal(
      additionalNodeGroupFields.some((input) => input.id === "desired_size"),
      false,
    );
    const additionalMinSize = findInput(additionalNodeGroupFields, "min_size");
    const additionalMaxSize = findInput(additionalNodeGroupFields, "max_size");
    assert.equal(additionalMinSize.label, "Minimum nodes");
    assert.equal(additionalMaxSize.label, "Maximum nodes");
    assert.match(String(additionalMinSize.description), /spare capacity/);
    assert.match(String(additionalMaxSize.description), /pods can remain pending/);
    assert.equal(findInput(clusterInputs, "system_node_min_size").label, "Minimum nodes");
    assert.equal(findInput(clusterInputs, "system_node_max_size").label, "Maximum nodes");
    assert.equal(findInput(clusterInputs, "system_node_min_size").default, 2);
    assert.equal(findInput(clusterInputs, "system_node_max_size").default, 4);
    assert.match(String(findInput(clusterInputs, "system_node_min_size").description), /spare capacity/);
    assert.match(String(findInput(clusterInputs, "system_node_max_size").description), /pods can remain pending/);
    for (const inputId of [
      "system_node_capacity_type",
      "system_node_instance_types",
      "system_node_min_size",
      "system_node_max_size",
      "system_node_disk_size",
    ]) {
      assert.equal(findInput(clusterInputs, inputId).collapsible, true, `${inputId} should be collapsible`);
    }
    assert.equal(clusterInputs.some((input) => input.id === "section_system_nodes"), false);
    assert.equal(clusterInputs.some((input) => input.id === "section_application_capacity"), false);
    assert.match(String(findInput(clusterInputs, "section_capacity").description), /0\.5 vCPU and 1 GiB/);
    assert.ok(clusterInputs.findIndex((input) => input.id === "section_capacity") < clusterInputs.findIndex((input) => input.id === "system_node_capacity_type"));
    assert.ok(clusterInputs.findIndex((input) => input.id === "system_node_capacity_type") < clusterInputs.findIndex((input) => input.id === "system_node_instance_types"));
    assert.ok(clusterInputs.findIndex((input) => input.id === "system_node_disk_size") < clusterInputs.findIndex((input) => input.id === "node_groups"));
    assert.equal(clusterInputs.some((input) => input.id === "section_endpoint"), false);
    assert.ok(clusterInputs.findIndex((input) => input.id === "section_access") < clusterInputs.findIndex((input) => input.id === "endpoint_private_access_enabled"));
    assert.ok(clusterInputs.findIndex((input) => input.id === "section_fargate") < clusterInputs.findIndex((input) => input.id === "section_access"));
    assert.ok(clusterInputs.findIndex((input) => input.id === "access_entries") < clusterInputs.findIndex((input) => input.id === "section_observability"));
    assert.equal(clusterInputs.some((input) => input.id === "ravion_runner_security_group_creation_enabled"), false);
    assert.equal(clusterInputs.some((input) => input.id === "public_access_cidrs"), false);
    assert.equal(clusterInputs.some((input) => input.id === "enabled_cluster_log_types"), false);
    assert.equal(clusterInputs.some((input) => input.id === "cluster_log_retention_in_days"), false);

    const systemNodeInstanceTypes = findInput(clusterInputs, "system_node_instance_types");
    assert.equal(systemNodeInstanceTypes.type, "string_array");
    assert.deepEqual(systemNodeInstanceTypes.default, ["t3.medium"]);
    assert.equal(
      systemNodeInstanceTypes.values,
      "$values:aws/ec2/instances?awsAccountId=<<module.input.aws_account_id>>&region=<<module.input.aws_region>>",
    );
    assert.equal(
      findInput(additionalNodeGroupFields, "instance_types").values,
      systemNodeInstanceTypes.values,
    );

    const fargateProfiles = findInput(clusterInputs, "fargate_profiles");
    assert.equal(fargateProfiles.type, "object_map");
    const fargateProfileFields = (fargateProfiles.item_inputs as unknown[]).map((input) =>
      assertRecord(input, "fargate_profiles.item_inputs[]"),
    );
    const fargateSelectors = findInput(fargateProfileFields, "selectors");
    assert.equal(fargateSelectors.type, "object_array");
    assert.equal(fargateSelectors.required, true);
    assert.equal(fargateSelectors.add_button_label, undefined);
    const fargateSelectorFields = (fargateSelectors.item_inputs as unknown[]).map((input) =>
      assertRecord(input, "fargate_profiles.selectors.item_inputs[]"),
    );
    assert.equal(findInput(fargateSelectorFields, "namespace").required, true);
    assert.equal(findInput(fargateSelectorFields, "labels").type, "keyvalue");
    assert.equal(findInput(fargateProfileFields, "subnet_ids").type, "string_array");
    assert.equal(findInput(fargateProfileFields, "pod_execution_role_arn").type, "string");

    const accessEntries = findInput(clusterInputs, "access_entries");
    assert.equal(accessEntries.type, "object_map");
    const accessEntryFields = (accessEntries.item_inputs as unknown[]).map((input) =>
      assertRecord(input, "access_entries.item_inputs[]"),
    );
    assert.equal(findInput(accessEntryFields, "principal_arn").required, true);
    const policyAssociations = findInput(accessEntryFields, "policy_associations");
    assert.equal(policyAssociations.type, "object_map");
    const policyAssociationFields = (policyAssociations.item_inputs as unknown[]).map((input) =>
      assertRecord(input, "access_entries.policy_associations.item_inputs[]"),
    );
    assert.equal(findInput(policyAssociationFields, "policy_arn").required, true);
    assert.equal(findInput(policyAssociationFields, "access_scope_type").default, "cluster");
    assert.deepEqual(findInput(policyAssociationFields, "access_scope_namespaces").show_when, {
      access_scope_type: "namespace",
    });

    const systemNodeGroup = assertRecord(getTerraformVariable(cluster.module, "system_node_group"), "system_node_group");
    assert.equal(systemNodeGroup.instance_types, "<< module.input.system_node_instance_types >>");
    assert.equal("desired_size" in systemNodeGroup, false);
    assert.equal(getTerraformVariable(cluster.module, "ravion_runner_security_group_creation_enabled"), undefined);

    const karpenterNodePool = assertRecord(
      getTerraformVariable(addons.module, "karpenter_default_node_pool"),
      "karpenter_default_node_pool",
    );
    assert.equal(
      karpenterNodePool.capacity_types,
      '<< module.input.karpenter_default_node_pool_capacity_types != nil ? module.input.karpenter_default_node_pool_capacity_types : ["on-demand", "spot"] >>',
    );

    const addonsInputs = getModuleInputs(addons.module);
    const addonsCluster = findInput(addonsInputs, "cluster");
    const addonsClusterMappedInputs = (addonsCluster.mapped_inputs as unknown[]).map((input) =>
      assertRecord(input, "addons.cluster.mapped_inputs[]"),
    );
    const runnerSecurityGroup = findInput(addonsClusterMappedInputs, "ravion_runner_security_group_id");
    assert.equal(runnerSecurityGroup.default, "<<ref.stack.output.ravion_runner_security_group_id>>");
    assert.equal(runnerSecurityGroup.immutable, true);

    const addonsStack = assertRecord(addons.module.stack, "addons.module.stack");
    const addonsPipelines = assertRecord(addonsStack.pipelines, "addons.module.stack.pipelines");
    const addonsDefaults = assertRecord(addonsPipelines.defaults, "addons.module.stack.pipelines.defaults");
    const addonsPipelineInput = assertRecord(addonsDefaults.input, "addons.module.stack.pipelines.defaults.input");
    assert.deepEqual(addonsPipelineInput.execution_environment_overrides, {
      security_group: "<< module.input.ravion_runner_security_group_id >>",
    });

    const addonsUi = assertRecord(addons.module.ui, "addons.module.ui");
    const addonsMetrics = addonsUi.metrics;
    assert.ok(Array.isArray(addonsMetrics), "addons.module.ui.metrics should be an array");
    for (const metric of addonsMetrics) {
      const metricRecord = assertRecord(metric, "addons.module.ui.metrics[]");
      const source = assertRecord(metricRecord.source, `addons metric ${String(metricRecord.id)} source`);
      assert.equal(source.type, "amp", `addons metric ${String(metricRecord.id)} should use the AMP source`);
    }

    const deploy = assertRecord(web.module.deploy, "module.deploy");
    const webInputs = getModuleInputs(web.module);
    const computeTarget = findInput(webInputs, "compute_target");
    assert.equal(computeTarget.default, "any");
    assert.deepEqual(computeTarget.moved_from, ["capacity_type"]);
    assert.deepEqual(getValueOptions(computeTarget), ["any", "on_demand", "spot", "fargate"]);
    const clusterInput = findInput(webInputs, "cluster");
    const mappedInputs = (clusterInput.mapped_inputs as unknown[]).map((input) =>
      assertRecord(input, "cluster.mapped_inputs[]"),
    );
    const clusterPrivateSubnetIds = findInput(mappedInputs, "cluster_private_subnet_ids");
    assert.equal(clusterPrivateSubnetIds.required, true);
    assert.deepEqual(clusterPrivateSubnetIds.show_when, { compute_target: "fargate" });
    const definition = assertRecord(deploy.definition, "module.deploy.definition");
    const values = assertRecord(definition.values, "module.deploy.definition.values");
    assert.equal(
      values.affinity,
      '<< module.input.compute_target == "on_demand" || module.input.compute_target == "spot" ? {"nodeAffinity":{"requiredDuringSchedulingIgnoredDuringExecution":{"nodeSelectorTerms":[{"matchExpressions":[{"key":"eks.amazonaws.com/capacityType","operator":"In","values":[module.input.compute_target == "spot" ? "SPOT" : "ON_DEMAND"]}]},{"matchExpressions":[{"key":"karpenter.sh/capacity-type","operator":"In","values":[module.input.compute_target == "spot" ? "spot" : "on-demand"]}]}]}}} : {} >>',
    );
    assert.equal(
      values.podLabels,
      '<< module.input.compute_target == "fargate" ? {"eks.amazonaws.com/fargate-profile": module.input.name + "-fargate"} : {} >>',
    );
    assert.equal(
      values.podAnnotations,
      '<< module.input.compute_target == "on_demand" || module.input.compute_target == "spot" ? {"eks.amazonaws.com/compute-type": "ec2"} : {} >>',
    );
    assert.equal(
      getTerraformVariable(web.module, "fargate_profile"),
      '<< module.input.compute_target == "fargate" ? {"name": module.input.name + "-fargate", "subnet_ids": module.input.cluster_private_subnet_ids, "selectors": [{"namespace": module.input.namespace, "labels": {"app.kubernetes.io/instance": module.input.name}}]} : nil >>',
    );
  });

  it("compiles concise EKS add-on guidance and input constraints", async () => {
    const compiled = await compileDefinitionFile(
      join(repoRoot, "compute", "eks", "addons", "rvn-eks-addons-definition.yml"),
    );
    const inputs = getModuleInputs(compiled.module);

    const nodeLifetime = findInput(inputs, "karpenter_default_node_pool_expire_after");
    assert.match(String(nodeLifetime.description), /1h30m.*720h.*Never/);
    assert.deepEqual(nodeLifetime.patterns, [
      {
        message: "Use integer segments with s, m, or h, such as 1h30m or 720h, or Never.",
        pattern: "^(([0-9]+(s|m|h))+|Never)$",
      },
    ]);

    const lokiRetention = findInput(inputs, "loki_retention_days");
    assert.equal(lokiRetention.min, 1);
    assert.equal(lokiRetention.max, 3650);
    assert.equal(lokiRetention.collapsible, true);
    assert.equal(inputs.some((input) => input.id === "log_retention_days"), false);
    assert.equal(findInput(inputs, "karpenter_default_node_pool_creation_enabled").collapsible, true);
    assert.equal(findInput(inputs, "prometheus_retention_days").min, 1);
    assert.match(
      String(findInput(inputs, "cloudwatch_application_signals_namespaces").description),
      /does not add injection annotations/,
    );
    const operator = findInput(inputs, "ravion_operator_enabled");
    assert.equal(inputs.some((input) => input.id === "ravion_operator_deploy_enabled"), false);
    assert.equal(operator.default, true);
    assert.deepEqual(operator.moved_from, ["beacon_enabled"]);
    for (const id of [
      "ravion_operator_execution_jobs_enabled",
      "ravion_operator_namespaces_creation_enabled",
      "ravion_operator_deploy_namespaces",
      "ravion_operator_self_update_enabled",
      "ravion_operator_full_management_enabled",
      "ravion_operator_execution_image",
      "ravion_operator_chart_version",
      "ravion_operator_execution_max_concurrent",
      "ravion_operator_coordinator_enabled",
      "ravion_operator_coordinator_adaptive_enabled",
      "ravion_operator_coordinator_replicas",
      "ravion_operator_coordinator_distinct_nodes_enabled",
    ]) {
      assert.equal(inputs.some((input) => input.id === id), false, `${id} is managed automatically`);
    }
    assert.equal(
      getTerraformVariable(compiled.module, "ravion_operator_chart_version"),
      "0.4.1-ci.c111d232df7b",
    );
    for (const id of ["ravion_operator_execution_jobs_enabled", "ravion_operator_full_management_enabled", "ravion_operator_coordinator_enabled"]) {
      assert.equal(getTerraformVariable(compiled.module, id), true);
    }
    for (const id of ["ravion_operator_namespaces_creation_enabled", "ravion_operator_self_update_enabled", "ravion_operator_deploy_namespaces"]) {
      assert.equal(getTerraformVariable(compiled.module, id), undefined, `${id} uses its Terraform default`);
    }
    assert.deepEqual(findInput(inputs, "logs_excluded_namespaces").default, [
      "kube-system", "kube-node-lease", "amazon-cloudwatch", "ravion-operator", "ravion-beacon",
    ]);
    assert.equal(
      getTerraformVariable(compiled.module, "logs_excluded_namespaces"),
      '<< module.input.logs_excluded_namespaces != nil ? module.input.logs_excluded_namespaces : ["kube-system", "kube-node-lease", "amazon-cloudwatch", "ravion-operator", "ravion-beacon"] >>',
    );
    assert.equal(findInput(inputs, "public_alb_creation_enabled").default, true);
    assert.equal(inputs.some((input) => input.id === "public_nlb_security_group_ids"), false);
    assert.equal(inputs.some((input) => input.id === "private_nlb_security_group_ids"), false);
    assert.equal(inputs.some((input) => input.id === "amp_region"), false);
    assert.equal(inputs.some((input) => input.id === "beacon_enabled"), false);
    assert.equal(inputs.some((input) => input.id === "beacon_deploy_enabled"), false);
    assert.equal(inputs.some((input) => input.id === "beacon_deploy_namespaces"), false);
    assert.equal(
      getTerraformVariable(compiled.module, "ravion_operator_deploy_enabled"),
      getTerraformVariable(compiled.module, "ravion_operator_enabled"),
    );
    for (const legacyVariable of [
      "beacon_enabled",
      "beacon_deploy_enabled",
      "beacon_deploy_namespaces",
      "beacon_project_id",
      "beacon_environment_id",
      "beacon_aws_account_record_id",
    ]) {
      assert.equal(getTerraformVariable(compiled.module, legacyVariable), undefined);
    }
    for (const sectionId of ["section_ravion_operator", "section_karpenter", "section_external_secrets"]) {
      assert.doesNotMatch(String(findInput(inputs, sectionId).description), /Terraform runner/);
    }
    assert.doesNotMatch(JSON.stringify(compiled), /\bBeacon\b/);

    for (const definitionName of ["rvn-eks-web", "rvn-eks-worker", "rvn-eks-cron"]) {
      const workload = await compileDefinitionFile(
        join(repoRoot, "compute", "eks_service", `${definitionName}-definition.yml`),
      );
      assert.doesNotMatch(JSON.stringify(workload), /\bBeacon\b/, `${definitionName} uses retired Beacon terminology`);
    }

    for (const input of inputs) {
      if (typeof input.description === "string") {
        assert.doesNotMatch(input.description, /on by default/i, `${String(input.id)} repeats its visible default`);
      }
    }
  });

  it("places EKS add-on load balancers below Ravion EKS Management", async () => {
    const compiled = await compileDefinitionFile(
      join(repoRoot, "compute", "eks", "addons", "rvn-eks-addons-definition.yml"),
    );
    const inputs = getModuleInputs(compiled.module);
    const indexOf = (id: string) => inputs.findIndex((input) => input.id === id);

    assert.equal(indexOf("section_alb"), indexOf("ravion_operator_enabled") + 1);
    assert.ok(indexOf("section_alb") < indexOf("section_nlb"));
    assert.ok(indexOf("section_nlb") < indexOf("aws_load_balancer_controller_chart_version"));
    assert.ok(indexOf("aws_load_balancer_controller_chart_version") < indexOf("section_karpenter"));
  });

  it("keeps EKS section descriptions only for cross-field guidance", async () => {
    const definitions = [
      {
        path: ["compute", "eks", "rvn-eks-cluster-definition.yml"],
        sectionIds: ["section_capacity"],
      },
      {
        path: ["compute", "eks", "addons", "rvn-eks-addons-definition.yml"],
        sectionIds: [
          "section_ravion_operator",
          "section_alb",
          "section_nlb",
          "section_karpenter",
          "section_grafana",
          "section_external_secrets",
        ],
      },
      {
        path: ["compute", "eks_service", "rvn-eks-web-definition.yml"],
        sectionIds: [],
      },
      {
        path: ["compute", "eks_service", "rvn-eks-worker-definition.yml"],
        sectionIds: [],
      },
      {
        path: ["compute", "eks_service", "rvn-eks-cron-definition.yml"],
        sectionIds: [],
      },
    ];

    for (const definition of definitions) {
      const compiled = await compileDefinitionFile(join(repoRoot, ...definition.path));
      const describedSections = getModuleInputs(compiled.module)
        .filter((input) => input.type === "section" && typeof input.description === "string")
        .map((input) => input.id);

      assert.deepEqual(describedSections, definition.sectionIds, `${compiled.type} has redundant section guidance`);
    }
  });

  it("groups EKS add-ons with cluster selection", async () => {
    for (const definitionName of ["rvn-eks-web", "rvn-eks-worker", "rvn-eks-cron"]) {
      const compiled = await compileDefinitionFile(
        join(repoRoot, "compute", "eks_service", `${definitionName}-definition.yml`),
      );
      const inputs = getModuleInputs(compiled.module);
      const clusterIndex = inputs.findIndex((input) => input.id === "cluster");
      const addonsIndex = inputs.findIndex((input) => input.id === "addons");
      const serviceSectionIndex = inputs.findIndex((input) => input.id === "section_service");

      assert.equal(addonsIndex, clusterIndex + 1, `${definitionName} should place add-ons after cluster`);
      assert.ok(addonsIndex < serviceSectionIndex, `${definitionName} should keep add-ons in the cluster section`);
      assert.equal(inputs.some((input) => input.id === "section_addons"), false);
      assert.equal(inputs.some((input) => input.id === "create_namespace"), false);
    }
  });

  it("compiles focused KMS inputs with complete key user ARN validation", async () => {
    const compiled = await compileDefinitionFile(join(repoRoot, "security", "kms", "rvn-aws-kms-definition.yml"));
    const inputs = getModuleInputs(compiled.module);
    const input = findInput(inputs, "key_user_role_arns");
    const validArns = [
      "arn:aws:iam::123456789012:root",
      "arn:aws-us-gov:iam::123456789012:role/team/application",
      "arn:aws-cn:iam::123456789012:user/developer",
    ];
    const invalidArns = [
      "arn:aws:iam::",
      "arn:aws:iam::12345678901:root",
      "arn:aws:iam::123456789012:role/",
      "arn:aws:iam::123456789012:group/developers",
    ];

    assert.ok(Array.isArray(input.patterns), "key_user_role_arns.patterns should be an array");
    assert.equal(input.patterns.length, 1);
    const validation = assertRecord(input.patterns[0], "key_user_role_arns.patterns[0]");
    const pattern = new RegExp(assertString(validation.pattern));

    for (const arn of validArns) assert.match(arn, pattern, `key_user_role_arns should accept ${arn}`);
    for (const arn of invalidArns) assert.doesNotMatch(arn, pattern, `key_user_role_arns should reject ${arn}`);

    const specializedInputIds = [
      "alias",
      "deletion_window_in_days",
      "description",
      "key_administrator_role_arns",
      "key_configuration",
      "key_rotation_enabled",
      "multi_region_enabled",
      "public_key_reader_role_arns",
      "signer_role_arns",
    ];
    for (const inputId of specializedInputIds) {
      assert.equal(inputs.some((candidate) => candidate.id === inputId), false);
    }

    const specializedTerraformVariables = [
      "alias",
      "deletion_window_in_days",
      "description",
      "key_administrator_role_arns",
      "key_rotation_enabled",
      "key_spec",
      "key_usage",
      "multi_region_enabled",
      "public_key_reader_role_arns",
      "signer_role_arns",
    ];
    for (const variableName of specializedTerraformVariables) {
      assert.equal(getTerraformVariable(compiled.module, variableName), undefined);
    }
  });

  it("fails when a local token remains after compilation", async () => {
    await assert.rejects(
      compileDefinitionFile(join(fixturesDir, "invalid-local-token.yml")),
      (error) => error instanceof CompileError && error.message.includes("module.stack.source.ref"),
    );
  });

  it("detects include cycles with a readable path chain", async () => {
    await assert.rejects(
      compileDefinitionFile(join(fixturesDir, "invalid-cycle.yml")),
      (error) => error instanceof CompileError && error.message.includes("include cycle detected") && error.message.includes("cycle-a.yml"),
    );
  });

  it("fails when a $with token is embedded in a template string", async () => {
    await assert.rejects(
      compileDefinitionFile(join(fixturesDir, "invalid-with-token.yml")),
      (error) => error instanceof CompileError && error.message.includes("$with tokens must occupy the entire string"),
    );
  });

  it("compiles Railpack inputs and builder object for ECS image builds", async () => {
    const compiled = await compileDefinitionFile(join(repoRoot, "compute", "ecs_service", "rvn-ecs-web-definition.yml"));
    const inputs = getModuleInputs(compiled.module);

    assert.deepEqual(getValueOptions(findInput(inputs, "build_source")), ["dockerfile", "railpack", "image_registry"]);
    assert.deepEqual(getBuildSourceShowWhen(findInput(inputs, "source_repo")), ["dockerfile", "railpack"]);

    const basePath = findInput(inputs, "source_base_path");
    assert.equal(basePath.label, "Source base path");
    assert.deepEqual(getBuildSourceShowWhen(basePath), ["dockerfile", "railpack"]);

    const railpackVersion = findInput(inputs, "railpack_version");
    assert.equal(railpackVersion.label, "Railpack version");
    assert.equal(getBuildSourceShowWhen(railpackVersion), "railpack");
    assert.deepEqual(railpackVersion.patterns, [
      {
        message: "Leave blank, use latest, a semantic version like 0.29.0, or a v-prefixed version like v0.29.0.",
        pattern: "^(|latest|v?[0-9]+\\.[0-9]+\\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?)$",
      },
    ]);

    for (const inputId of ["railpack_install_cmd", "railpack_build_cmd", "railpack_start_cmd"]) {
      assert.equal(getBuildSourceShowWhen(findInput(inputs, inputId)), "railpack");
    }

    assert.deepEqual(getBuildSourceShowWhen(findInput(inputs, "section_builder_config")), ["dockerfile", "railpack", "nixpacks"]);
    assert.deepEqual(getBuildSourceShowWhen(findInput(inputs, "section_ecr")), ["dockerfile", "railpack", "nixpacks"]);
    assert.equal(findInput(inputs, "min_capacity").label, "Minimum tasks");
    assert.equal(findInput(inputs, "max_capacity").label, "Maximum tasks");

    const build = getModuleBuild(compiled.module);
    const builder = assertString(build.builder);
    assert.match(builder, /module\.input\.build_source == "railpack"/);
    assert.match(builder, /module\.input\.build_source == "nixpacks"/);
    assert.match(builder, /\{type: "railpack", railpack_version:/);
    assert.match(builder, /install_cmd: module\.input\.railpack_install_cmd/);
    assert.match(builder, /build_cmd: module\.input\.railpack_build_cmd/);
    assert.match(builder, /start_cmd:\s+module\.input\.railpack_start_cmd/);
    assert.match(builder, /cache_from: \{tag: "railpack"\}/);

    const railpackBranch = builder.slice(builder.indexOf('module.input.build_source == "railpack"'), builder.indexOf(': {type: "disabled"}'));
    assert.doesNotMatch(railpackBranch, /nixpacks_/);
    assert.doesNotMatch(railpackBranch, /build_path/);

    const ecrRepositoryCreationEnabled = getTerraformVariable(compiled.module, "ecr_repository_creation_enabled");
    assert.equal(
      ecrRepositoryCreationEnabled,
      '<< module.input.build_source == "dockerfile" || module.input.build_source == "railpack" || module.input.build_source == "nixpacks" >>',
    );
  });

  it("gates the Lambda ECR repository on build source and seeds image-registry creates from an initial ref", async () => {
    const compiled = await compileDefinitionFile(join(repoRoot, "compute", "lambda", "rvn-lambda-definition.yml"));
    const inputs = getModuleInputs(compiled.module);

    const initialImageRef = findInput(inputs, "initial_image_ref");
    assert.equal(initialImageRef.label, "Initial image tag or digest");
    assert.equal(initialImageRef.required, true);
    assert.equal(getBuildSourceShowWhen(initialImageRef), "image_registry");

    assert.deepEqual(getBuildSourceShowWhen(findInput(inputs, "section_ecr")), ["dockerfile", "nixpacks"]);
    assert.deepEqual(getBuildSourceShowWhen(findInput(inputs, "ecr_scan_on_push_enabled")), ["dockerfile", "nixpacks"]);
    assert.deepEqual(getBuildSourceShowWhen(findInput(inputs, "ecr_force_deletion_enabled")), ["dockerfile", "nixpacks"]);

    assert.equal(
      getTerraformVariable(compiled.module, "ecr_repository_creation_enabled"),
      '<< module.input.lambda_type != "edge" && module.input.package_type == "Image" && module.input.build_source != "image_registry" >>',
    );

    const imageUri = assertString(getTerraformVariable(compiled.module, "image_uri"));
    assert.match(imageUri, /module\.input\.build_source == "image_registry"/);
    assert.match(imageUri, /module\.input\.initial_image_ref contains "sha256:"/);
    assert.match(imageUri, /module\.input\.image_repository \+ "@" \+ module\.input\.initial_image_ref/);
    assert.match(imageUri, /module\.input\.image_repository \+ ":" \+ module\.input\.initial_image_ref/);
  });

  it("compiles Railpack inputs and builder object for static builds", async () => {
    const compiled = await compileDefinitionFile(join(repoRoot, "hosting", "static_site", "rvn-aws-static-definition.yml"));
    const inputs = getModuleInputs(compiled.module);

    assert.deepEqual(getValueOptions(findInput(inputs, "build_source")), ["railpack", "dockerfile", "s3_directory"]);
    assert.deepEqual(getBuildSourceShowWhen(findInput(inputs, "source_repo")), ["dockerfile", "railpack", "nixpacks"]);
    assert.deepEqual(getBuildSourceShowWhen(findInput(inputs, "output_directory")), ["dockerfile", "railpack", "nixpacks"]);
    assert.deepEqual(getBuildSourceShowWhen(findInput(inputs, "build_environment_variables")), ["dockerfile", "railpack", "nixpacks"]);

    for (const inputId of ["railpack_version", "railpack_install_cmd", "railpack_build_cmd"]) {
      assert.deepEqual(getBuildSourceShowWhen(findInput(inputs, inputId)), ["railpack", "nixpacks"]);
    }
    assert.equal(inputs.some((input) => input.id === "railpack_start_cmd"), false);

    const build = getModuleBuild(compiled.module);
    const builder = assertString(build.builder);
    assert.match(builder, /module\.input\.build_source == "railpack"/);
    assert.match(builder, /module\.input\.build_source == "nixpacks"/);
    assert.match(builder, /\{type: "railpack", railpack_version:/);
    assert.match(builder, /install_cmd: module\.input\.railpack_install_cmd/);
    assert.match(builder, /build_cmd: module\.input\.railpack_build_cmd/);
    assert.match(builder, /output_directory: module\.input\.output_directory/);
    assert.doesNotMatch(builder, /start_cmd/);
    assert.doesNotMatch(builder, /cache_from: \{tag: "railpack"\}/);
  });

  it("compiles primary ALB certificate references, additional SNI certificates, and visibility-aware ingress defaults", async () => {
    const [alb, cluster] = await Promise.all([
      compileDefinitionFile(join(repoRoot, "networking", "alb", "rvn-aws-alb-definition.yml")),
      compileDefinitionFile(join(repoRoot, "compute", "ecs_cluster", "rvn-ecs-cluster-definition.yml")),
    ]);
    const albInputs = getModuleInputs(alb.module);

    assert.equal(findInput(albInputs, "internal_load_balancer_enabled").label, "Internal load balancer");
    assert.equal(findInput(albInputs, "http_listener_enabled").label, "HTTP");
    assert.equal(findInput(albInputs, "https_listener_enabled").label, "HTTPS");
    assert.ok(findInput(albInputs, "http_listener_port"));
    assert.ok(findInput(albInputs, "https_listener_port"));

    const certificate = findInput(albInputs, "certificate");
    assert.equal(certificate.type, "$ref:rvn-acm-certificate");
    assert.equal(certificate.required, true);
    assert.deepEqual(certificate.show_when, { https_listener_enabled: true });
    const certificateMappedInputs = certificate.mapped_inputs;
    assert.ok(Array.isArray(certificateMappedInputs), "certificate.mapped_inputs should be an array");
    const certificateArns = assertRecord(certificateMappedInputs[0], "certificate ARN mapped input");
    assert.equal(certificateArns.id, "certificate_arns");
    assert.equal(certificateArns.type, "string_array");
    assert.deepEqual(certificateArns.default, ["<<ref.stack.output.certificate_arn>>"]);
    const additionalCertificateArns = findInput(albInputs, "additional_certificate_arns");
    assert.equal(additionalCertificateArns.type, "string_array");
    assert.deepEqual(additionalCertificateArns.default, []);
    assert.deepEqual(additionalCertificateArns.show_when, { https_listener_enabled: true });

    const clusterInputs = getModuleInputs(cluster.module);
    for (const [inputId, mappedInputId, additionalInputId] of [
      ["public_alb_certificate", "public_alb_certificate_arns", "public_alb_additional_certificate_arns"],
      ["private_alb_certificate", "private_alb_certificate_arns", "private_alb_additional_certificate_arns"],
    ]) {
      const clusterCertificate = findInput(clusterInputs, inputId);
      assert.equal(clusterCertificate.type, "$ref:rvn-acm-certificate");
      const mappedInputs = clusterCertificate.mapped_inputs;
      assert.ok(Array.isArray(mappedInputs), `${inputId}.mapped_inputs should be an array`);
      const mappedInput = assertRecord(mappedInputs[0], `${inputId} ARN mapped input`);
      assert.equal(mappedInput.id, mappedInputId);
      assert.equal(mappedInput.type, "string_array");
      assert.deepEqual(findInput(clusterInputs, additionalInputId).default, []);
    }

    assert.match(
      assertString(getTerraformVariable(alb.module, "certificate_arns")),
      /concat\(module\.input\.additional_certificate_arns/,
    );
    assert.match(
      assertString(getTerraformVariable(cluster.module, "public_alb_certificate_arns")),
      /concat\(module\.input\.public_alb_additional_certificate_arns/,
    );
    assert.match(
      assertString(getTerraformVariable(cluster.module, "private_alb_certificate_arns")),
      /concat\(module\.input\.private_alb_additional_certificate_arns/,
    );

    const ipv4Ingress = assertString(getTerraformVariable(alb.module, "ingress_cidr_blocks"));
    assert.match(ipv4Ingress, /ingress_cidr_blocks != nil/);
    assert.doesNotMatch(ipv4Ingress, /ingress_cidr_blocks != \[\]/);
    assert.match(ipv4Ingress, /internal_load_balancer_enabled/);
    assert.match(ipv4Ingress, /10\.0\.0\.0\/8/);
    assert.match(ipv4Ingress, /0\.0\.0\.0\/0/);

    const ipv6Ingress = assertString(getTerraformVariable(alb.module, "ingress_ipv6_cidr_blocks"));
    assert.match(ipv6Ingress, /internal_load_balancer_enabled \? \[\]/);
    assert.match(ipv6Ingress, /::\/0/);

    const ui = assertRecord(alb.module.ui, "module.ui");
    const links = assertString(ui.links);
    assert.match(links, /https_listener_enabled/);
    assert.match(links, /http_listener_enabled/);
    assert.match(links, /stack\.output\.alb_dns_name/);
  });

  it("compiles EC2 service load balancer source choices", async () => {
    const compiled = await compileDefinitionFile(
      join(repoRoot, "compute", "ec2_service", "rvn-ec2-service-definition.yml"),
    );
    const inputs = getModuleInputs(compiled.module);

    assert.equal(compiled.type, "rvn-ec2-service");
    assert.deepEqual(
      inputs.filter((input) => input.type === "section").map((input) => input.id),
      [
        "section_service",
        "section_build",
        "section_dockerfile",
        "section_railpack",
        "section_deployment",
        "section_web",
        "section_routing",
        "section_health",
        "section_storage",
        "section_scaling",
        "section_app_config",
        "section_networking",
        "section_builder_config",
        "section_ecr",
        "section_logging",
        "section_advanced",
      ],
    );

    for (const inputId of [
      "deployment_concurrency_max",
      "deployment_errors_max",
      "target_group_slow_start",
      "target_group_stickiness_type",
      "target_group_stickiness_cookie_name",
      "health_check_grace_period",
      "direct_access_cidr_blocks",
      "data_volume_creation_enabled",
      "min_capacity",
      "max_capacity",
      "cpu_autoscaling_enabled",
      "ecr_scan_on_push_enabled",
    ]) {
      assert.ok(findInput(inputs, inputId), `expected EC2 service input ${inputId}`);
    }

    assert.deepEqual(getBuildSourceShowWhen(findInput(inputs, "section_builder_config")), ["dockerfile", "railpack"]);
    assert.deepEqual(findInput(inputs, "deploy_source_base_path").show_when, {
      deploy_type: "manual",
      deploy_source_repo: { not: "" },
    });
    assert.equal(inputs.some((input) => input.id === "min_size" || input.id === "max_size"), false);
    assert.equal(findInput(inputs, "min_capacity").label, "Minimum instances");
    assert.equal(findInput(inputs, "max_capacity").label, "Maximum instances");
    assert.equal(getTerraformVariable(compiled.module, "min_size"), "<< module.input.min_capacity >>");
    assert.equal(getTerraformVariable(compiled.module, "max_size"), "<< module.input.max_capacity >>");

    const imageRef = findInput(getDeployInputs(compiled.module), "image_ref");
    assert.deepEqual(imageRef.patterns, [
      {
        message: "Image tags and digests must not contain whitespace.",
        pattern: "^\\S+$",
      },
    ]);

    const loadBalancerSource = findInput(inputs, "load_balancer_source");
    assert.equal(loadBalancerSource.default, "standalone_alb");
    assert.equal(loadBalancerSource.immutable, true);
    assert.deepEqual(getValueOptions(loadBalancerSource), ["standalone_alb", "ecs_cluster"]);
      assert.deepEqual(loadBalancerSource.show_when, { http_traffic_enabled: true });

    const standaloneAlb = findInput(inputs, "alb");
    assert.equal(standaloneAlb.required, true);
    assert.deepEqual(standaloneAlb.show_when, {
      http_traffic_enabled: true,
      load_balancer_source: "standalone_alb",
    });
    const standaloneMappedInputs = standaloneAlb.mapped_inputs;
    assert.ok(Array.isArray(standaloneMappedInputs), "alb.mapped_inputs should be an array");
    assert.ok(
      standaloneMappedInputs.some((input) => assertRecord(input, "ALB mapped input").id === "alb_arn_suffix"),
      "expected standalone ALB ARN suffix mapping",
    );

    const ecsCluster = findInput(inputs, "ecs_cluster");
    assert.equal(ecsCluster.required, true);
    assert.equal(ecsCluster.immutable, true);
    assert.deepEqual(ecsCluster.show_when, {
      http_traffic_enabled: true,
      load_balancer_source: "ecs_cluster",
    });
    const clusterMappedInputs = ecsCluster.mapped_inputs;
    assert.ok(Array.isArray(clusterMappedInputs), "ecs_cluster.mapped_inputs should be an array");
    const clusterMappedInputIds = clusterMappedInputs.map((input) => assertRecord(input, "ECS cluster mapped input").id);
    for (const inputId of [
      "public_alb_http_listener_arn",
      "public_alb_https_listener_arn",
      "public_alb_security_group_id",
      "public_alb_arn_suffix",
      "private_alb_http_listener_arn",
      "private_alb_https_listener_arn",
      "private_alb_security_group_id",
      "private_alb_arn_suffix",
    ]) {
      assert.ok(clusterMappedInputIds.includes(inputId), `expected ECS cluster mapping ${inputId}`);
    }

    const clusterAlbVisibility = findInput(inputs, "ecs_cluster_alb_visibility");
    assert.equal(clusterAlbVisibility.default, "public");
    assert.equal(clusterAlbVisibility.immutable, undefined);
    assert.deepEqual(getValueOptions(clusterAlbVisibility), ["public", "private"]);
    assert.deepEqual(clusterAlbVisibility.show_when, {
      http_traffic_enabled: true,
      load_balancer_source: "ecs_cluster",
    });
    const loadBalancerAttachment = assertRecord(
      getTerraformVariable(compiled.module, "load_balancer_attachment"),
      "load_balancer_attachment",
    );
    const listenerRules = loadBalancerAttachment.listener_rules;
    assert.equal(loadBalancerAttachment.creation_enabled, "<< module.input.http_traffic_enabled >>");
    assert.ok(Array.isArray(listenerRules) && listenerRules.length === 1, "load balancer attachment should have one listener rule");
    const listenerArn = assertString(assertRecord(listenerRules[0], "listener rule").listener_arn);
    assert.match(listenerArn, /load_balancer_source == "standalone_alb"/);
    assert.match(listenerArn, /alb_https_listener_arn \|\| module\.input\.alb_http_listener_arn/);
    assert.match(listenerArn, /ecs_cluster_alb_visibility == "public"/);
    assert.match(listenerArn, /public_alb_https_listener_arn \|\| module\.input\.public_alb_http_listener_arn/);
    assert.match(listenerArn, /private_alb_https_listener_arn \|\| module\.input\.private_alb_http_listener_arn/);

    const targetGroup = assertRecord(loadBalancerAttachment.target_group, "load_balancer_attachment.target_group");
    assert.equal(targetGroup.slow_start, "<< module.input.target_group_slow_start >>");
    const stickiness = assertString(targetGroup.stickiness);
    assert.match(stickiness, /module\.input\.target_group_stickiness_type/);
    assert.match(stickiness, /module\.input\.target_group_stickiness_cookie_name/);

    const loadBalancerSecurityGroupId = assertString(
      getTerraformVariable(compiled.module, "load_balancer_security_group_id"),
    );
    assert.match(loadBalancerSecurityGroupId, /load_balancer_source == "standalone_alb"/);
    assert.match(loadBalancerSecurityGroupId, /alb_security_group_id/);
    assert.match(loadBalancerSecurityGroupId, /public_alb_security_group_id/);
    assert.match(loadBalancerSecurityGroupId, /private_alb_security_group_id/);

    const ecrRepositoryCreationEnabled = assertString(
      getTerraformVariable(compiled.module, "ecr_repository_creation_enabled"),
    );
    assert.match(ecrRepositoryCreationEnabled, /module\.input\.deploy_type == "container"/);
    assert.equal(
      getTerraformVariable(compiled.module, "ecr_scan_on_push_enabled"),
      "<< module.input.ecr_scan_on_push_enabled >>",
    );
    assert.equal(
      getTerraformVariable(compiled.module, "health_check_grace_period"),
      "<< module.input.health_check_grace_period >>",
    );
    assert.match(
      assertString(getTerraformVariable(compiled.module, "direct_access_cidr_blocks")),
      /module\.input\.http_traffic_enabled/,
    );
    assert.equal(
      getTerraformVariable(compiled.module, "public_ip_assignment_enabled"),
      "<< module.input.private_subnet_placement_enabled ? false : true >>",
    );
    assert.equal(
      getTerraformVariable(compiled.module, "data_volume_creation_enabled"),
      "<< module.input.data_volume_creation_enabled >>",
    );
    assert.match(
      assertString(getTerraformVariable(compiled.module, "deploy_health_check_path")),
      /module\.input\.health_check_path/,
    );
    assert.match(
      assertString(getTerraformVariable(compiled.module, "container_start_command")),
      /module\.input\.container_start_command/,
    );

    const deploy = assertRecord(compiled.module.deploy, "module.deploy");
    assert.equal(deploy.timeout, 86400);
    assert.deepEqual(deploy.concurrency, { queue_overflow: "oldest", queue_size: 1 });
    assert.deepEqual(deploy.strategy, {
      type: "rolling",
      concurrency_max: "<< module.input.deployment_concurrency_max >>",
      errors_max: "<< module.input.deployment_errors_max >>",
    });

    const ui = assertRecord(compiled.module.ui, "module.ui");
    const metrics = assertString(ui.metrics);
    assert.match(metrics, /module\.input\.http_traffic_enabled/);
    assert.match(metrics, /GroupDesiredCapacity/);
    assert.match(metrics, /GroupInServiceInstances/);
    assert.match(metrics, /LoadBalancer:/);
    assert.match(metrics, /TargetGroup:/);
    assert.match(metrics, /HTTPCode_Target_4XX_Count/);
    assert.match(metrics, /UnHealthyHostCount/);
    assert.doesNotMatch(metrics, /namespace:"AWS\/EC2"/);
  });

  it("propagates shared build input guidance to every consumer", async () => {
    const definitionPaths = [
      ["compute", "ec2_service", "rvn-ec2-service-definition.yml"],
      ["compute", "ecs_service", "rvn-ecs-nlb-definition.yml"],
      ["compute", "ecs_service", "rvn-ecs-web-definition.yml"],
      ["compute", "ecs_service", "rvn-ecs-worker-definition.yml"],
      ["compute", "eks_service", "rvn-eks-cron-definition.yml"],
      ["compute", "eks_service", "rvn-eks-web-definition.yml"],
      ["compute", "eks_service", "rvn-eks-worker-definition.yml"],
      ["compute", "lambda", "rvn-lambda-definition.yml"],
      ["hosting", "static_site", "rvn-aws-static-definition.yml"],
    ];
    const definitions = await Promise.all(definitionPaths.map((path) => compileDefinitionFile(join(repoRoot, ...path))));

    for (const definition of definitions) {
      const inputs = getModuleInputs(definition.module);
      assert.equal(
        findInput(inputs, "source_repo").description,
        "Repository containing the application source for Dockerfile or Railpack builds.",
        `${definition.type} should include shared Git source guidance`,
      );

      const builderType = findInput(inputs, "build_capacity_type");
      assert.equal(
        builderType.description,
        "Use on-demand EC2 for predictable availability or EC2 Spot for lower cost with possible capacity delays or interruption.",
        `${definition.type} should include shared builder guidance`,
      );
      const builderOptions = builderType.values;
      assert.ok(Array.isArray(builderOptions), `${definition.type} builder type should have values`);
      assert.deepEqual(
        builderOptions.map((option) => {
          const value = assertRecord(option, `${definition.type} builder option`);
          return [value.value, value.description];
        }),
        [
          ["ec2", "Use on-demand capacity for predictable availability without Spot interruption."],
          ["ec2-spot", "Use lower-cost Spot capacity that can wait for capacity or be interrupted by AWS."],
        ],
      );
      for (const removedInputId of [
        "build_infrastructure_type",
        "build_instance_size",
        "build_ami",
        "dockerfile_inject_env_variables",
      ]) {
        assert.equal(inputs.some((input) => input.id === removedInputId), false);
      }
      assert.equal(
        findInput(inputs, "build_default_policies_enabled").collapsible,
        true,
        `${definition.type} should keep default build policies in collapsible builder settings`,
      );
    }

    for (const definition of definitions.filter((candidate) => candidate.type !== "rvn-lambda")) {
      const inputs = getModuleInputs(definition.module);
      assert.equal(
        findInput(inputs, "railpack_install_cmd").description,
        "Optional dependency installation command. Leave blank to use Railpack detection.",
      );
      assert.equal(
        findInput(inputs, "railpack_build_cmd").description,
        "Optional application build command. Leave blank to use Railpack detection.",
      );
    }
  });

  it("compiles rolling ECS NLB services with per-listener configuration", async () => {
    const compiled = await compileDefinitionFile(join(repoRoot, "compute", "ecs_service", "rvn-ecs-nlb-definition.yml"));
    const listeners = findInput(getModuleInputs(compiled.module), "listeners");
    const itemInputs = listeners.item_inputs;
    assert.ok(Array.isArray(itemInputs), "listeners.item_inputs should be an array");

    const tlsCertificate = findInput(
      itemInputs.map((input) => assertRecord(input, "listeners.item_inputs[]")),
      "tls_certificate",
    );
    assert.equal(tlsCertificate.type, "$ref:rvn-acm-certificate");
    assert.deepEqual(tlsCertificate.show_when, { listener_protocol: "TLS" });

    const loadBalancerAttachment = assertRecord(
      getTerraformVariable(compiled.module, "load_balancer_attachment"),
      "load_balancer_attachment",
    );
    const nlbListeners = assertString(loadBalancerAttachment.nlb_listeners);
    assert.match(nlbListeners, /map\(module\.input\.listeners/);
    assert.match(nlbListeners, /#\.tls_certificate_arn/);

    const deploy = assertRecord(compiled.module.deploy, "module.deploy");
    assert.equal(deploy.strategy, undefined);
    assert.deepEqual(deploy.infrastructure, {
      ecs_cluster_arn: "<<stack.output.service_cluster>>",
      ecs_service_arn: "<<stack.output.service_arn>>",
    });

    const taskDefinition = assertRecord(deploy.task_definition, "module.deploy.task_definition");
    const containerDefinitions = assertString(taskDefinition.container_definitions);
    assert.match(containerDefinitions, /port_mappings": map\(module\.input\.listeners/);
    assert.doesNotMatch(containerDefinitions, /module\.input\.container_port/);
  });
});

function getModuleInputs(module: Record<string, unknown>): Record<string, unknown>[] {
  const inputs = module.inputs;
  assert.ok(Array.isArray(inputs), "module.inputs should be an array");
  return inputs.map((input) => {
    assert.ok(isRecord(input), "module input should be an object");
    return input;
  });
}

function getModuleBuild(module: Record<string, unknown>): Record<string, unknown> {
  assert.ok(isRecord(module.build), "module.build should be an object");
  return module.build;
}

function getDeployInputs(module: Record<string, unknown>): Record<string, unknown>[] {
  const deploy = assertRecord(module.deploy, "module.deploy");
  const inputs = deploy.inputs;
  assert.ok(Array.isArray(inputs), "module.deploy.inputs should be an array");
  return inputs.map((input) => assertRecord(input, "deploy input"));
}

function findInput(inputs: Record<string, unknown>[], id: string): Record<string, unknown> {
  const input = inputs.find((candidate) => candidate.id === id);
  assert.ok(input, `expected input ${id}`);
  return input;
}

function getValueOptions(input: Record<string, unknown>): unknown[] {
  const values = input.values;
  assert.ok(Array.isArray(values), `${String(input.id)} should have values`);
  return values.map((value) => {
    assert.ok(isRecord(value), "value option should be an object");
    return value.value;
  });
}

function getBuildSourceShowWhen(input: Record<string, unknown>): unknown {
  const showWhen = assertRecord(input.show_when, `${String(input.id)}.show_when`);
  return showWhen.build_source;
}

function getTerraformVariable(module: Record<string, unknown>, key: string): unknown {
  const stack = assertRecord(module.stack, "module.stack");
  const pipelines = assertRecord(stack.pipelines, "module.stack.pipelines");
  const defaults = assertRecord(pipelines.defaults, "module.stack.pipelines.defaults");
  const input = assertRecord(defaults.input, "module.stack.pipelines.defaults.input");
  const terraformVariables = assertRecord(input.terraform_variables, "module.stack.pipelines.defaults.input.terraform_variables");
  return terraformVariables[key];
}

function assertString(value: unknown): string {
  if (typeof value !== "string") {
    assert.fail("expected string");
  }
  return value;
}

function assertRecord(value: unknown, name: string): Record<string, unknown> {
  assert.ok(isRecord(value), `${name} should be an object`);
  return value;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
