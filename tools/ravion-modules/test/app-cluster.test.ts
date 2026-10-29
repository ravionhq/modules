import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { describe, it } from "node:test";
import YAML from "yaml";
import { compileDefinitionFile } from "../src/compiler.js";

const repoRoot = resolve(process.cwd(), "../..");
const modulePath = resolve(repoRoot, "compute/app_cluster");
const definitionPath = resolve(modulePath, "rvn-aws-app-cluster-definition.yml");

const ROUTER_METRICS_NAMESPACE = "Ravion/AppRouter";

// Every metric the app router publishes in ROUTER_METRICS_NAMESPACE, as the
// runner names them (flightcontrol packages/runner/internal/approuter,
// metrics.go). A chart that names anything else reads a series nobody writes.
const ROUTER_METRIC_NAMES = [
  "Requests",
  "Responses2xx",
  "Responses3xx",
  "Responses4xx",
  "Responses5xx",
  "Latency",
  "UnknownHostnameRequests",
  "Wakes",
  "WakeFailures",
  "WakeDuration",
  "HeldRequests",
  "OpenWebSockets",
  "Routes",
  "ControlPlaneConnected",
  "MemoryUsedMiB",
  "RouterInstanceCPUUtilization",
  "RouterInstanceMemoryUtilization",
  "RouterInstanceNetworkInBytes",
  "RouterInstanceNetworkOutBytes",
];

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

describe("rvn-aws-app-cluster module definition", () => {
  it("is an unreleased 0.x module with inputs, outputs, a stack, an apps block, charts and a readme", async () => {
    const definition = await compileDefinitionFile(definitionPath);

    assert.equal(definition.type, "rvn-aws-app-cluster");
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

    assert.deepEqual(Object.keys(apps).sort(), [
      "awsAccountId",
      "customDomains",
      "defaults",
      "domain",
      "executionEnvironmentId",
      "limits",
      "loadBalancer",
      "region",
      "router",
      "vpcId",
    ]);
    assert.deepEqual(Object.keys(record(apps.loadBalancer)).sort(), ["dnsName", "tlsListenerArn", "zoneId"]);
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

  it("hands Ravion the chosen execution environment, where the cluster runs, its domains, load balancer and router", async () => {
    const definition = await compileDefinitionFile(definitionPath);
    const apps = record(definition.module.apps);

    // The execution environment is the input the user chose, never something
    // the stack creates: its sandbox pool runs the apps.
    assert.equal(apps.executionEnvironmentId, "<< module.input.execution_environment_id >>");
    assert.equal(apps.awsAccountId, "<< module.input.aws_account_id >>");
    assert.equal(apps.region, "<< module.output.region >>");
    assert.equal(apps.vpcId, "<< module.input.vpc_id >>");
    assert.equal(apps.domain, "<< module.output.wildcard_domain_name >>");
    assert.equal(apps.customDomains, "<< module.output.custom_domain_apexes >>");
    assert.deepEqual(record(apps.loadBalancer), {
      tlsListenerArn: "<< module.output.tls_listener_arn >>",
      dnsName: "<< module.output.load_balancer_dns_name >>",
      zoneId: "<< module.output.load_balancer_zone_id >>",
    });
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
    assert.equal(outputs.find((output) => output.id === "custom_domain_apexes")?.type, "string_array");
    assert.equal(outputs.find((output) => output.id === "tls_listener_arn")?.type, "string");
    for (const id of ["execution_environment_id", "host_security_group_id"]) {
      assert.equal(declared.has(id), false, `unexpected output ${id}`);
      assert.equal(outputsFile.includes(`output "${id}"`), false, `unexpected Terraform output ${id}`);
    }
  });

  it("passes every Terraform variable it sets to a variable of the module", async () => {
    const definition = await compileDefinitionFile(definitionPath);
    const variables = terraformVariables(definition.module);
    const variablesFile = (await terraformFiles()).get("variables.tf") ?? "";

    for (const name of Object.keys(variables).filter((key) => key !== "...overrides")) {
      assert.ok(variablesFile.includes(`variable "${name}"`), `expected Terraform variable ${name}`);
    }
  });

  it("runs the router in the network's private subnets and the load balancer in its public ones", async () => {
    const definition = await compileDefinitionFile(definitionPath);
    const variables = terraformVariables(definition.module);

    assert.equal(variables.router_subnet_ids, "<< module.input.private_subnet_ids >>");
    assert.equal(variables.public_subnet_ids, "<< module.input.public_subnet_ids >>");
  });

  it("runs the apps on the sandbox pool of an execution environment the user chooses, the network's by default", async () => {
    const definition = await compileDefinitionFile(definitionPath);
    const network = findInput(records(definition.module.inputs), "network");
    const executionEnvironment = findInput(records(network.mapped_inputs), "execution_environment_id");

    assert.equal(executionEnvironment.label, "Execution environment");
    assert.equal(executionEnvironment.type, "string");
    assert.equal(executionEnvironment.values, "$values:ravion/execution_environments");
    assert.equal(executionEnvironment.default, "<< ref.input.execution_environment_id >>");
    // The apps' sandboxes live in its pool, and Ravion cannot move them to
    // another one.
    assert.equal(executionEnvironment.required, true);
    assert.equal(executionEnvironment.immutable, true);
    assert.equal(executionEnvironment.collapsible, undefined);
    assert.match(String(executionEnvironment.description), /sandbox pool/);
    // Terraform runs in it too, as in every module.
    const input = record(record(record(record(definition.module.stack).pipelines).defaults).input);
    assert.equal(input.execution_environment_id, "<< module.input.execution_environment_id >>");
  });

  it("keeps the other mapped network inputs as the shared network partial has them", async () => {
    const definition = await compileDefinitionFile(definitionPath);
    const network = findInput(records(definition.module.inputs), "network");
    const partial: unknown = YAML.parse(await readFile(resolve(repoRoot, "partials/templates/network-ref-mapped-inputs.yml"), "utf8"));
    const withDefaults = new Map([
      ["$with.aws_account_id_default", "<< ref.input.aws_account_id >>"],
      ["$with.aws_region_default", "<< ref.input.aws_region >>"],
      ["$with.private_subnet_ids_default", "<<ref.stack.output.private_subnet_ids>>"],
      ["$with.public_subnet_ids_default", "<<ref.stack.output.public_subnet_ids>>"],
      ["$with.vpc_id_default", "<<ref.stack.output.vpc_id>>"],
    ]);
    const expected = records(partial)
      .filter((input) => input.id !== "execution_environment_id")
      .map((input) => (typeof input.default === "string" && withDefaults.has(input.default) ? { ...input, default: withDefaults.get(input.default) } : input));

    assert.deepEqual(
      records(network.mapped_inputs).filter((input) => input.id !== "execution_environment_id"),
      expected,
    );
  });

  it("creates no pool, no hosts and no hosts' security group: the execution environment has them", async () => {
    const definition = await compileDefinitionFile(definitionPath);
    const files = await terraformFiles();
    const terraform = [...files.values()].join("\n");
    const inputIds = new Set(records(definition.module.inputs).map((input) => input.id));
    const variables = terraformVariables(definition.module);

    assert.equal(files.has("sandbox_pool.tf"), false);
    assert.equal(terraform.includes("ravion_sandbox_pool"), false);
    assert.equal(terraform.includes('resource "aws_security_group" "sandbox_hosts"'), false);
    // The router's way in to the hosts is a rule Ravion adds to the execution
    // environment's security group while the router runs; the stack adds
    // ingress rules to its own groups only.
    for (const match of terraform.matchAll(/resource "aws_vpc_security_group_ingress_rule" "([a-z_]+)"/g)) {
      assert.ok(["load_balancer", "router"].includes(match[1]), `unexpected ingress rule ${match[1]}`);
    }
    for (const name of ["host_subnet_id", "host_instance_types", "host_capacity_types", "host_reserve_policy", "max_hosts"]) {
      assert.equal(terraform.includes(`variable "${name}"`), false, `unexpected variable ${name}`);
      assert.equal(name in variables, false, `unexpected Terraform variable ${name}`);
    }
    for (const id of ["section_hosts", "host_instance_types", "host_capacity_types", "warm_hosts", "warm_host_count", "warm_host_window_days", "max_hosts"]) {
      assert.equal(inputIds.has(id), false, `unexpected input ${id}`);
    }
  });

  it("serves the apps under custom wildcard domains entered in the Domain section", async () => {
    const definition = await compileDefinitionFile(definitionPath);
    const inputs = records(definition.module.inputs);
    const variables = terraformVariables(definition.module);
    const ids = inputs.map((input) => input.id);
    const domains = findInput(inputs, "domains");

    assert.ok(ids.indexOf("domains") > ids.indexOf("section_domain") && ids.indexOf("domains") < ids.indexOf("section_router"));
    assert.equal(domains.label, "Custom domains");
    assert.equal(domains.type, "string_array");
    assert.equal(domains.placeholder, "*.apps.example.com");
    assert.equal(domains.add_button_label, "Add custom domain");
    // One certificate covers every custom domain, and it takes at most 10 names.
    assert.equal(domains.max_length, 10);
    assert.equal(domains.required, undefined);
    assert.equal(variables.domains, "<< module.input.domains || [] >>");

    const patterns = records(domains.patterns).map((pattern) => new RegExp(String(pattern.pattern)));
    assert.ok(patterns.length > 0);
    for (const accepted of ["*.apps.example.com", "*.example.com", "*.a-b.c0.example.org"]) {
      assert.ok(
        patterns.every((pattern) => pattern.test(accepted)),
        `expected ${accepted} to be accepted`,
      );
    }
    for (const refused of ["apps.example.com", "*.com", "*.apps.*.example.com", "*.-apps.example.com", "**.apps.example.com", "*.Apps.example.com", "*.apps.example.com."]) {
      assert.ok(
        patterns.some((pattern) => !pattern.test(refused)),
        `expected ${refused} to be refused`,
      );
    }
  });

  it("needs only the ravion provider's released 0.0.3-rc.1 and the resources it has", async () => {
    const files = await terraformFiles();
    const versions = files.get("versions.tf") ?? "";
    const terraform = [...files.values()].join("\n");
    const lock = await readFile(resolve(modulePath, ".terraform.lock.hcl"), "utf8");

    assert.match(versions, /source\s+=\s+"providers\.ravion\.com\/ravion\/ravion"/);
    assert.match(versions, /version\s+=\s+"= 0\.0\.3-rc\.1"/);
    assert.equal(/dev registry|DEV ONLY|siddharthsuresh/i.test(versions), false);

    // The lock file pins the release with the registry's checksums, which a
    // Ravion runner on linux_amd64 verifies.
    const start = lock.indexOf('provider "providers.ravion.com/ravion/ravion" {');
    assert.ok(start >= 0, "expected the ravion provider in the lock file");
    const block = lock.slice(start, lock.indexOf("\n}\n", start));
    assert.match(block, /version\s+=\s+"0\.0\.3-rc\.1"/);
    assert.match(block, /constraints\s+=\s+"0\.0\.3-rc\.1"/);
    assert.match(block, /"zh:[0-9a-f]{64}"/);

    // ravion_aws_acm_certificate and ravion_domain are the release's
    // resources; anything else would need a newer provider.
    const ravionTypes = new Set([...terraform.matchAll(/(?:resource|data) "(ravion_[a-z_]+)"/g)].map((match) => match[1]));
    assert.deepEqual([...ravionTypes].sort(), ["ravion_aws_acm_certificate", "ravion_domain"]);
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
        // The instance the router runs on. While Ravion replaces it, two
        // instances publish under one Router: the maximum shows the busier
        // one's share, and the sums add both instances' bytes.
        ["router_instance_cpu", "RouterInstanceCPUUtilization", "Maximum", undefined],
        ["router_instance_memory", "RouterInstanceMemoryUtilization", "Maximum", undefined],
        ["router_instance_network_in", "RouterInstanceNetworkInBytes", "Sum", undefined],
        ["router_instance_network_out", "RouterInstanceNetworkOutBytes", "Sum", undefined],
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

  it("charts every metric the router publishes, under the names it publishes them", async () => {
    const definition = await compileDefinitionFile(definitionPath);
    const charted = new Set(chartsIn(definition.module, ROUTER_METRICS_NAMESPACE).map((chart) => record(chart.source).name));

    assert.deepEqual([...charted].filter((name) => !ROUTER_METRIC_NAMES.includes(String(name))), []);
    assert.deepEqual(
      ROUTER_METRIC_NAMES.filter((name) => !charted.has(name)),
      [],
    );
    for (const chart of chartsIn(definition.module, ROUTER_METRICS_NAMESPACE)) {
      const groupBy = record(chart.source).group_by;
      // The router's dimensions are Router, App and Hostname; the cluster's
      // charts split by Hostname at most, an app's page by App.
      assert.ok(groupBy === undefined || groupBy === "Hostname", `unexpected group_by ${String(groupBy)}`);
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

  it("charts the execution environment's pool host minutes from the series its hosts publish", async () => {
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
      assert.deepEqual(record(chart.source).dimensions, { ExecutionEnvironmentId: "<< module.input.execution_environment_id >>" });
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
