import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { join, resolve } from "node:path";
import { compileAllDefinitions, CompileError, compileDefinitionFile } from "../src/compiler.js";

const fixturesDir = join(process.cwd(), "test", "fixtures", "compile");
const repoRoot = resolve(process.cwd(), "../..");

describe("compiler", () => {
  it("compiles one definition file to canonical module config", async () => {
    const compiled = await compileDefinitionFile(join(fixturesDir, "modules", "networking", "vpc", "ravion-aws-vpc-definition.yml"));

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
                repo: "https://github.com/flightcontrolhq/modules",
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
          repo: "https://github.com/flightcontrolhq/modules",
          ref: "ravion-aws-vpc@1.2.3",
          base_path: "networking/vpc",
        },
      },
      deploy: {
        strategy: "rolling",
      },
      readme: "Terraform source https://github.com/flightcontrolhq/modules/tree/ravion-aws-vpc@1.2.3/networking/vpc",
      settings: {
        advanced: {
          retries: 2,
        },
      },
    });
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
    for (const arrayInputId of ["public_albs", "private_albs"]) {
      const albArray = findInput(clusterInputs, arrayInputId);
      assert.equal(albArray.type, "object_array");
      const itemInputs = albArray.item_inputs;
      assert.ok(Array.isArray(itemInputs), `${arrayInputId}.item_inputs should be an array`);
      const certificate = assertRecord(
        itemInputs.find((item) => assertRecord(item, "item input").id === "certificate"),
        `${arrayInputId} certificate item input`,
      );
      assert.equal(certificate.type, "$ref:rvn-acm-certificate");
      const mappedInputs = certificate.mapped_inputs;
      assert.ok(Array.isArray(mappedInputs), `${arrayInputId} certificate.mapped_inputs should be an array`);
      const mappedInput = assertRecord(mappedInputs[0], `${arrayInputId} certificate ARN mapped input`);
      assert.equal(mappedInput.id, "certificate_arns");
      assert.equal(mappedInput.type, "string_array");
      const additionalCertificates = assertRecord(
        itemInputs.find(
          (item) => assertRecord(item, "item input").id === "additional_certificate_arns",
        ),
        `${arrayInputId} additional certificate ARNs item input`,
      );
      assert.equal(additionalCertificates.type, "string_array");
    }

    assert.match(
      assertString(getTerraformVariable(alb.module, "certificate_arns")),
      /concat\(module\.input\.additional_certificate_arns/,
    );
    for (const arrayInputId of ["public_albs", "private_albs"]) {
      const mapping = assertString(getTerraformVariable(cluster.module, arrayInputId));
      assert.match(mapping, /certificate_arns/);
      assert.match(mapping, /additional_certificate_arns/);
    }

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

      const builderType = findInput(inputs, "build_infrastructure_type");
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
