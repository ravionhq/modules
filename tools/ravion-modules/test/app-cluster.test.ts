import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { describe, it } from "node:test";
import { compileDefinitionFile } from "../src/compiler.js";

const repoRoot = resolve(process.cwd(), "../..");
const modulePath = resolve(repoRoot, "compute/app_cluster");
const definitionPath = resolve(modulePath, "rvn-app-cluster-definition.yml");

const ROUTER_METRICS_NAMESPACE = "Ravion/AppRouter";

function record(value: unknown): Record<string, unknown> {
  assert.ok(value !== null && typeof value === "object" && !Array.isArray(value));
  return Object.fromEntries(Object.entries(value));
}

function records(value: unknown): Record<string, unknown>[] {
  assert.ok(Array.isArray(value));
  return value.map(record);
}

function findInput(inputs: Record<string, unknown>[], id: string): Record<string, unknown> {
  const input = inputs.find((candidate) => candidate.id === id);
  assert.ok(input, `expected input ${id}`);
  return input;
}

function templateLeaves(value: unknown): string[] {
  if (typeof value === "string") {
    return [value];
  }
  if (Array.isArray(value)) {
    return value.flatMap(templateLeaves);
  }
  if (value === null || typeof value !== "object") {
    return [];
  }
  return Object.values(record(value)).flatMap(templateLeaves);
}

function terraformVariables(module: Record<string, unknown>): Record<string, unknown> {
  const pipelines = record(record(module.stack).pipelines);
  return record(record(record(pipelines.defaults).input).terraform_variables);
}

function charts(module: Record<string, unknown>): Record<string, unknown>[] {
  return records(record(module.ui).metrics);
}

function chartsIn(module: Record<string, unknown>, namespace: string): Record<string, unknown>[] {
  return charts(module).filter((chart) => record(chart.source).namespace === namespace);
}

async function terraformFiles(): Promise<Map<string, string>> {
  const names = (await readdir(modulePath)).filter((name) => name.endsWith(".tf"));
  return new Map(await Promise.all(names.map(async (name) => [name, await readFile(resolve(modulePath, name), "utf8")] as const)));
}

describe("rvn-app-cluster module definition", () => {
  it("is an unreleased 0.x module with inputs, outputs, a stack, an apps block, charts and a readme", async () => {
    const definition = await compileDefinitionFile(definitionPath);

    assert.equal(definition.type, "rvn-app-cluster");
    assert.equal(definition.name, "App Cluster");
    assert.equal(definition.global, false);
    assert.match(definition.version, /^0\./);
    assert.deepEqual(Object.keys(definition.module).sort(), ["apps", "inputs", "outputs", "readme", "stack", "ui"]);
  });

  it("deploys the Terraform in compute/app_cluster", async () => {
    const definition = await compileDefinitionFile(definitionPath);
    const input = record(record(record(record(definition.module.stack).pipelines).defaults).input);

    assert.equal(input.base_path, "compute/app_cluster");
  });

  it("fills every field of the App Cluster definition, and nothing else, with whole templates", async () => {
    const definition = await compileDefinitionFile(definitionPath);
    const apps = record(definition.module.apps);

    assert.deepEqual(Object.keys(apps).sort(), ["defaults", "domain", "executionEnvironmentId", "limits", "router"]);
    assert.deepEqual(Object.keys(record(apps.router)).sort(), [
      "instanceProfileName",
      "instanceType",
      "redirectTargetGroupArn",
      "securityGroupId",
      "subnetIds",
      "trafficTargetGroupArn",
    ]);
    assert.deepEqual(Object.keys(record(apps.defaults)).sort(), ["cpu", "diskGib", "idleTimeoutSeconds", "memoryMib"]);
    assert.deepEqual(Object.keys(record(apps.limits)).sort(), ["cpu", "diskGib", "idleTimeoutSeconds", "memoryMib", "retentionSeconds"]);

    // An unquoted YAML value stops at " #", and a template that is not the
    // whole value is a string, not the number or list the field takes.
    for (const template of templateLeaves(apps)) {
      assert.match(template, /^<< [^#]* >>$/s);
      // Platform reads resolve the block from the module's own inputs and
      // outputs only.
      for (const namespace of template.matchAll(/\b([a-z_]+)\.(input|output)\b/g)) {
        assert.equal(namespace[1], "module", `unexpected namespace in ${template}`);
      }
    }
  });

  it("hands Ravion the stack's pool, domain and router resources", async () => {
    const definition = await compileDefinitionFile(definitionPath);
    const apps = record(definition.module.apps);

    assert.equal(apps.executionEnvironmentId, "<< module.output.execution_environment_id >>");
    assert.equal(apps.domain, "<< module.output.wildcard_domain_name >>");
    assert.deepEqual(record(apps.router), {
      instanceType: "<< module.input.router_instance_type >>",
      subnetIds: "<< module.output.router_subnet_ids >>",
      securityGroupId: "<< module.output.router_security_group_id >>",
      instanceProfileName: "<< module.output.router_instance_profile_name >>",
      trafficTargetGroupArn: "<< module.output.traffic_target_group_arn >>",
      redirectTargetGroupArn: "<< module.output.redirect_target_group_arn >>",
    });
  });

  it("converts the form's GiB, minutes and days to the MiB and seconds the platform reads", async () => {
    const definition = await compileDefinitionFile(definitionPath);
    const apps = record(definition.module.apps);

    assert.deepEqual(record(apps.defaults), {
      cpu: "<< module.input.app_cpu >>",
      memoryMib: "<< module.input.app_memory * 1024 >>",
      diskGib: "<< module.input.app_disk >>",
      idleTimeoutSeconds: "<< module.input.app_idle_timeout * 60 >>",
    });
    assert.deepEqual(record(apps.limits), {
      cpu: "<< module.input.max_cpu >>",
      memoryMib: "<< module.input.max_memory * 1024 >>",
      diskGib: "<< module.input.max_disk >>",
      idleTimeoutSeconds: "<< module.input.max_idle_timeout * 60 >>",
      retentionSeconds: "<< module.input.retention_days * 86400 >>",
    });
  });

  it("defaults apps to 2 vCPUs, 4 GiB, 20 GiB and 15 minutes idle, within 8 vCPUs, 16 GiB, 100 GiB, a day idle and a week paused", async () => {
    const definition = await compileDefinitionFile(definitionPath);
    const inputs = records(definition.module.inputs);

    assert.deepEqual(
      ["app_cpu", "app_memory", "app_disk", "app_idle_timeout", "max_cpu", "max_memory", "max_disk", "max_idle_timeout", "retention_days"].map(
        (id) => [id, findInput(inputs, id).type, findInput(inputs, id).default],
      ),
      [
        ["app_cpu", "number", 2],
        ["app_memory", "number", 4],
        ["app_disk", "number", 20],
        ["app_idle_timeout", "number", 15],
        ["max_cpu", "number", 8],
        ["max_memory", "number", 16],
        ["max_disk", "number", 100],
        ["max_idle_timeout", "number", 1440],
        ["retention_days", "number", 7],
      ],
    );
    assert.equal(findInput(inputs, "router_instance_type").default, "t3.micro");
  });

  it("reads only inputs it declares", async () => {
    const definition = await compileDefinitionFile(definitionPath);
    const inputs = records(definition.module.inputs);
    const declared = new Set(
      inputs.flatMap((input) => [input.id, ...(Array.isArray(input.mapped_inputs) ? records(input.mapped_inputs).map((mapped) => mapped.id) : [])]),
    );

    const read = [definition.module.apps, definition.module.ui, terraformVariables(definition.module)]
      .flatMap(templateLeaves)
      .flatMap((template) => [...template.matchAll(/module\.input\.([a-z_]+)/g)].map((match) => match[1]));
    assert.ok(read.length > 0);
    assert.deepEqual(
      read.filter((id) => !declared.has(id)),
      [],
    );
  });

  it("reads only outputs it declares, and declares only outputs the Terraform has", async () => {
    const definition = await compileDefinitionFile(definitionPath);
    const outputs = records(definition.module.outputs);
    const declared = new Set(outputs.map((output) => output.id));
    const outputsFile = (await terraformFiles()).get("outputs.tf") ?? "";

    const read = [definition.module.apps, definition.module.ui]
      .flatMap(templateLeaves)
      .flatMap((template) => [...template.matchAll(/module\.output\.([a-z_]+)/g)].map((match) => match[1]));
    assert.deepEqual(
      read.filter((id) => !declared.has(id)),
      [],
    );
    for (const output of outputs) {
      assert.ok(outputsFile.includes(`output "${String(output.id)}"`), `expected Terraform output ${String(output.id)}`);
    }
    assert.equal(outputs.find((output) => output.id === "router_subnet_ids")?.type, "string_array");
    assert.equal(outputs.find((output) => output.id === "host_security_group_id")?.type, "string");
  });

  it("passes every Terraform variable it sets to a variable of the module", async () => {
    const definition = await compileDefinitionFile(definitionPath);
    const variables = terraformVariables(definition.module);
    const variablesFile = (await terraformFiles()).get("variables.tf") ?? "";

    for (const name of Object.keys(variables).filter((key) => key !== "...overrides")) {
      assert.ok(variablesFile.includes(`variable "${name}"`), `expected Terraform variable ${name}`);
    }
  });

  it("runs the router and the hosts in the network's private subnets and the load balancer in its public ones", async () => {
    const definition = await compileDefinitionFile(definitionPath);
    const variables = terraformVariables(definition.module);

    assert.equal(variables.router_subnet_ids, "<< module.input.private_subnet_ids >>");
    assert.equal(variables.host_subnet_id, "<< module.input.private_subnet_ids[0] >>");
    assert.equal(variables.public_subnet_ids, "<< module.input.public_subnet_ids >>");
  });

  it("configures the sandbox pool from the hosts section", async () => {
    const definition = await compileDefinitionFile(definitionPath);
    const inputs = records(definition.module.inputs);
    const variables = terraformVariables(definition.module);

    const instanceTypes = findInput(inputs, "host_instance_types");
    assert.equal(instanceTypes.type, "object_array");
    assert.deepEqual(instanceTypes.default, []);
    assert.deepEqual(
      records(instanceTypes.item_inputs).map((item) => [item.id, item.default]),
      [
        ["type", undefined],
        ["disk_gib", 130],
        ["disk_iops", 3000],
        ["disk_throughput_mbps", 125],
      ],
    );
    assert.equal(variables.host_instance_types, "<< module.input.host_instance_types || [] >>");

    const markets = findInput(inputs, "host_capacity_types");
    assert.deepEqual(markets.default, ["ON_DEMAND"]);
    assert.deepEqual(
      records(markets.values).map((value) => value.value),
      ["ON_DEMAND", "SPOT"],
    );

    const warmHosts = findInput(inputs, "warm_hosts");
    assert.equal(warmHosts.default, "NONE");
    assert.deepEqual(
      records(warmHosts.values).map((value) => value.value),
      ["NONE", "FIXED", "PEAK", "ROLLING_AVERAGE"],
    );
    assert.deepEqual(findInput(inputs, "warm_host_count").show_when, { warm_hosts: "FIXED" });
    assert.deepEqual(findInput(inputs, "warm_host_window_days").show_when, { warm_hosts: ["PEAK", "ROLLING_AVERAGE"] });
    assert.match(String(variables.host_reserve_policy), /^<< \{"type": module\.input\.warm_hosts \|\| "NONE", /);

    assert.equal(findInput(inputs, "max_hosts").default, 10);
    assert.equal(variables.max_hosts, "<< module.input.max_hosts >>");
  });

  it("registers the sandbox pool with the attributes the provider's ravion_sandbox_pool resource takes", async () => {
    const pool = (await terraformFiles()).get("sandbox_pool.tf") ?? "";
    const block = pool.slice(pool.indexOf('resource "ravion_sandbox_pool" "this" {'));
    const attributes = [...block.matchAll(/^ {2}([a-z_]+)\s+=/gm)].map((match) => match[1]);

    assert.deepEqual(attributes.sort(), [
      "aws_account_id",
      "capacity_types",
      "instance_types",
      "max_hosts",
      "region",
      "reserve_policy",
      "security_group_id",
      "subnet_id",
      "vpc_id",
    ]);
  });

  it("leaves the router instance to Ravion: no launch template, Auto Scaling group, instance or image to choose", async () => {
    const definition = await compileDefinitionFile(definitionPath);
    const files = [...(await terraformFiles()).values()].join("\n");

    for (const resource of ['resource "aws_launch_template"', 'resource "aws_autoscaling_group"', 'resource "aws_instance"', 'data "aws_ami"']) {
      assert.equal(files.includes(resource), false, `unexpected ${resource}`);
    }
    for (const variable of ["image_id", "image_owner", "image_name_pattern", "router_enabled", "instance_type", "sandbox_host_security_groups"]) {
      assert.equal(files.includes(`variable "${variable}"`), false, `unexpected variable ${variable}`);
    }
    const inputIds = new Set(records(definition.module.inputs).map((input) => input.id));
    for (const id of ["image_id", "image_owner", "router_enabled", "ssm_enabled", "sandbox_host_security_group_ids", "private_subnet_placement_enabled"]) {
      assert.equal(inputIds.has(id), false, `unexpected input ${id}`);
    }
  });

  it("charts the router's metrics for this cluster", async () => {
    const definition = await compileDefinitionFile(definitionPath);
    const metrics = chartsIn(definition.module, ROUTER_METRICS_NAMESPACE);

    assert.deepEqual(
      metrics.map((chart) => [chart.id, record(chart.source).name, record(chart.source).statistic, record(chart.source).group_by]),
      [
        ["requests", "Requests", "Sum", undefined],
        ["responses_2xx", "Responses2xx", "Sum", undefined],
        ["responses_3xx", "Responses3xx", "Sum", undefined],
        ["responses_4xx", "Responses4xx", "Sum", undefined],
        ["responses_5xx", "Responses5xx", "Sum", undefined],
        ["latency_average", "Latency", "Average", undefined],
        ["latency_maximum", "Latency", "Maximum", undefined],
        ["requests_by_hostname", "Requests", "Sum", "Hostname"],
        ["responses_5xx_by_hostname", "Responses5xx", "Sum", "Hostname"],
        ["unknown_hostname_requests", "UnknownHostnameRequests", "Sum", undefined],
        ["wakes", "Wakes", "Sum", undefined],
        ["wake_failures", "WakeFailures", "Sum", undefined],
        ["wake_duration", "WakeDuration", "Average", undefined],
        ["held_requests", "HeldRequests", "Maximum", undefined],
        ["open_websockets", "OpenWebSockets", "Maximum", undefined],
        ["routes", "Routes", "Maximum", undefined],
        // A 0/1 gauge: the minimum shows a disconnection anywhere in the period.
        ["control_plane_connected", "ControlPlaneConnected", "Minimum", undefined],
        ["router_memory", "MemoryUsedMiB", "Maximum", undefined],
      ],
    );
    for (const chart of metrics) {
      const source = record(chart.source);
      assert.equal(chart.type, "line");
      assert.equal(source.type, "cloudwatch");
      assert.equal(source.aws_account_id, "<< module.input.aws_account_id >>");
      assert.equal(source.region, "<< module.output.region >>");
      // The router publishes every datum under its cluster's module instance
      // id; grouped charts split that by one more dimension.
      assert.deepEqual(source.dimensions, { Router: "<< module.id >>" });
    }
  });

  it("charts the load balancer by its own dimensions", async () => {
    const definition = await compileDefinitionFile(definitionPath);
    const metrics = chartsIn(definition.module, "AWS/NetworkELB");

    assert.equal(metrics.length, 12);
    for (const chart of metrics) {
      assert.equal(record(record(chart.source).dimensions).LoadBalancer, "<< module.output.load_balancer_arn_suffix >>");
    }
  });

  it("charts the pool's host minutes from the series its hosts publish", async () => {
    const definition = await compileDefinitionFile(definitionPath);
    const metrics = chartsIn(definition.module, "Ravion/SandboxHost");

    // Each running host publishes one BusyHosts datum a minute under the
    // pool's execution environment: 1 while it holds a sandbox, else 0.
    assert.deepEqual(
      metrics.map((chart) => [chart.id, record(chart.source).name, record(chart.source).statistic]),
      [
        ["hosts_running", "BusyHosts", "SampleCount"],
        ["hosts_busy", "BusyHosts", "Sum"],
      ],
    );
    for (const chart of metrics) {
      assert.deepEqual(record(chart.source).dimensions, { ExecutionEnvironmentId: "<< module.output.execution_environment_id >>" });
    }
  });

  it("charts nothing keyed by an Auto Scaling group, which the router no longer has", async () => {
    const definition = await compileDefinitionFile(definitionPath);

    for (const chart of charts(definition.module)) {
      assert.equal("AutoScalingGroupName" in record(record(chart.source).dimensions), false, `unexpected ASG chart ${String(chart.id)}`);
    }
  });

  it("gives every chart its own id", async () => {
    const definition = await compileDefinitionFile(definitionPath);
    const ids = charts(definition.module).map((chart) => chart.id);

    assert.equal(new Set(ids).size, ids.length);
  });

  it("lets the router publish in the namespace its charts read and no other", async () => {
    const iamRole = (await terraformFiles()).get("iam_role.tf") ?? "";

    assert.ok(iamRole.includes(`"cloudwatch:namespace" = "${ROUTER_METRICS_NAMESPACE}"`));
  });

  it("says app, never preview", async () => {
    const definition = await compileDefinitionFile(definitionPath);
    const files = [...(await terraformFiles()).values()].join("\n");
    const readme = await readFile(resolve(modulePath, "README.md"), "utf8");

    for (const text of [JSON.stringify(definition), files, readme]) {
      assert.equal(/preview/i.test(text), false);
    }
  });
});
