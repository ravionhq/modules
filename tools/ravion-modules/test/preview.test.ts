import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { describe, it } from "node:test";
import { compileDefinitionFile } from "../src/compiler.js";

const repoRoot = resolve(process.cwd(), "../..");
const previewDefinitionPath = resolve(repoRoot, "compute/preview/rvn-preview-definition.yml");
const ingressDefinitionPath = resolve(repoRoot, "networking/preview_ingress/rvn-preview-ingress-definition.yml");

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
  return Object.values(record(value)).flatMap(templateLeaves);
}

function terraformVariables(module: Record<string, unknown>): Record<string, unknown> {
  const pipelines = record(record(module.stack).pipelines);
  return record(record(record(pipelines.defaults).input).terraform_variables);
}

describe("rvn-preview module definition", () => {
  it("is inputs and a preview block, with no stack, build or deploy", async () => {
    const definition = await compileDefinitionFile(previewDefinitionPath);

    assert.equal(definition.type, "rvn-preview");
    assert.equal(definition.name, "Preview");
    assert.equal(definition.global, false);
    assert.deepEqual(Object.keys(definition.module).sort(), ["inputs", "preview", "readme"]);
  });

  it("maps its inputs into every field of the preview block with whole templates", async () => {
    const definition = await compileDefinitionFile(previewDefinitionPath);
    const preview = record(definition.module.preview);

    assert.deepEqual(Object.keys(preview).sort(), [
      "expose",
      "idle",
      "ingress",
      "pull_requests",
      "retention",
      "sandbox",
      "source",
      "steps",
      "variables",
    ]);
    // An unquoted YAML value stops at " #", which cuts a template that uses the
    // "#" of map() in half.
    for (const template of templateLeaves(preview)) {
      assert.match(template, /^<< .* >>$/s);
    }
    assert.equal(preview.steps, "<< map(module.input.steps, #.command) >>");
    assert.equal(preview.ingress, "<< module.input.ingress >>");
    assert.equal(record(preview.sandbox).memoryMib, "<< module.input.sandbox_memory * 1024 >>");
  });

  it("reads only inputs it declares", async () => {
    const definition = await compileDefinitionFile(previewDefinitionPath);
    const inputs = records(definition.module.inputs);
    const declared = new Set(
      inputs.flatMap((input) => [input.id, ...(Array.isArray(input.mapped_inputs) ? records(input.mapped_inputs).map((mapped) => mapped.id) : [])]),
    );

    const read = templateLeaves(definition.module.preview).flatMap((template) =>
      [...template.matchAll(/module\.input\.([a-z_]+)/g)].map((match) => match[1]),
    );
    assert.ok(read.length > 0);
    assert.deepEqual(
      read.filter((id) => !declared.has(id)),
      [],
    );
  });

  it("takes steps as a required list and exposed ports as an optional one", async () => {
    const definition = await compileDefinitionFile(previewDefinitionPath);
    const inputs = records(definition.module.inputs);

    const steps = findInput(inputs, "steps");
    assert.equal(steps.type, "object_array");
    assert.equal(steps.required, true);
    assert.deepEqual(
      records(steps.item_inputs).map((item) => [item.id, item.type, item.required]),
      [["command", "text", true]],
    );

    const ports = findInput(inputs, "ports");
    assert.equal(ports.type, "object_array");
    assert.notEqual(ports.required, true);
    assert.deepEqual(ports.default, []);
    assert.deepEqual(
      records(ports.item_inputs).map((item) => item.id),
      ["name", "port", "health_check_path", "ravion_domain_name", "domains"],
    );
    assert.match(String(record(definition.module.preview).expose), /^<< map\(module\.input\.ports \|\| \[\], /);
  });

  it("asks for a preview ingress only to serve ports, so a module that exposes none can leave it unset", async () => {
    const definition = await compileDefinitionFile(previewDefinitionPath);
    const inputs = records(definition.module.inputs);

    const ingress = findInput(inputs, "ingress");
    assert.equal(ingress.type, "$ref:rvn-preview-ingress");
    assert.equal(ingress.required, false);
    assert.match(String(ingress.description), /exposes a port/);
    // An unset reference resolves to null, which the preview block takes as no ingress.
    assert.equal(record(definition.module.preview).ingress, "<< module.input.ingress >>");
    for (const mapped of records(ingress.mapped_inputs)) {
      assert.notEqual(mapped.required, true);
    }
  });

  it("keeps each port's domains inside the port, under the catalog's labels", async () => {
    const definition = await compileDefinitionFile(previewDefinitionPath);
    const inputs = records(definition.module.inputs);
    const portInputs = records(findInput(inputs, "ports").item_inputs);

    const ravionDomain = findInput(portInputs, "ravion_domain_name");
    assert.equal(ravionDomain.label, "Default Ravion domain");
    assert.equal(ravionDomain.type, "string");
    assert.notEqual(ravionDomain.required, true);

    const customDomains = findInput(portInputs, "domains");
    assert.equal(customDomains.label, "Custom domains");
    assert.equal(customDomains.type, "string_array");
    assert.equal(customDomains.max_length, 1);
    assert.equal(customDomains.add_button_label, "Add custom domain");

    // A top-level `domains` input beside a module reference is read by Ravion
    // as a service's own domain list.
    assert.equal(inputs.some((input) => input.id === "domains" || input.id === "ravion_domain_name"), false);
  });

  it("shows the ingress domain as the suffix of a port's Ravion domain, never as something to type", async () => {
    const definition = await compileDefinitionFile(previewDefinitionPath);
    const inputs = records(definition.module.inputs);

    const ingress = findInput(inputs, "ingress");
    assert.equal(ingress.type, "$ref:rvn-preview-ingress");
    const mapped = records(ingress.mapped_inputs);
    assert.deepEqual(
      mapped.map((input) => [input.id, input.default]),
      [["ingress_wildcard_domain_name", "<<ref.stack.output.wildcard_domain_name>>"]],
    );

    const ravionDomain = findInput(records(findInput(inputs, "ports").item_inputs), "ravion_domain_name");
    assert.equal(ravionDomain.suffix, ".<< module.input.ingress_wildcard_domain_name >>");
    assert.equal(ravionDomain.prefix, "{branch}-");
    assert.equal(JSON.stringify(definition.module.inputs).includes("platform.apex"), false);
  });

  it("takes environment variables in the catalog's runtime shape", async () => {
    const definition = await compileDefinitionFile(previewDefinitionPath);
    const inputs = records(definition.module.inputs);
    const runtimeInputs = records(
      (await compileDefinitionFile(resolve(repoRoot, "compute/eks_service/rvn-eks-worker-definition.yml"))).module.inputs,
    );

    const variables = findInput(inputs, "environment_variables");
    const runtimeVariables = findInput(runtimeInputs, "environment_variables");
    assert.equal(variables.type, runtimeVariables.type);
    assert.equal(variables.label, runtimeVariables.label);
    assert.equal(findInput(inputs, "section_app_config").label, findInput(runtimeInputs, "section_app_config").label);
    assert.equal(record(definition.module.preview).variables, "<< module.input.environment_variables || [] >>");
  });

  it("has no Terraform escape hatch", async () => {
    const definition = await compileDefinitionFile(previewDefinitionPath);

    assert.equal(JSON.stringify(definition.module.inputs).includes("advanced_terraform_variables"), false);
  });
});

describe("rvn-preview-ingress module definition", () => {
  it("takes custom wildcard domains under the catalog's label and hands them to Terraform", async () => {
    const definition = await compileDefinitionFile(ingressDefinitionPath);
    const inputs = records(definition.module.inputs);

    const domains = findInput(inputs, "domains");
    assert.equal(domains.label, "Custom domains");
    assert.equal(domains.type, "string_array");
    assert.equal(domains.max_length, 10);
    assert.equal(domains.add_button_label, "Add custom domain");
    assert.notEqual(domains.required, true);
    assert.equal(terraformVariables(definition.module).domains, "<< module.input.domains || [] >>");
  });

  it("checks custom domains in the form with the Terraform variable's pattern", async () => {
    const definition = await compileDefinitionFile(ingressDefinitionPath);
    const patterns = records(findInput(records(definition.module.inputs), "domains").patterns);
    const variablesFile = await readFile(resolve(repoRoot, "networking/preview_ingress/variables.tf"), "utf8");

    assert.equal(patterns.length, 1);
    const pattern = String(patterns[0].pattern);
    assert.ok(variablesFile.includes(`regex("${pattern.replaceAll("\\", "\\\\")}"`));

    const expression = new RegExp(pattern);
    for (const accepted of ["*.preview.example.com", "*.example.com", "*.pr-1.example.co.uk"]) {
      assert.ok(expression.test(accepted), `expected ${accepted} to be accepted`);
    }
    for (const refused of ["preview.example.com", "*.com", "*.*.example.com", "*.Preview.example.com", "*.preview_env.example.com", "*.example.com."]) {
      assert.equal(expression.test(refused), false, `expected ${refused} to be refused`);
    }
  });

  it("uses the same custom domain pattern as the preview module's ports", async () => {
    const ingress = await compileDefinitionFile(ingressDefinitionPath);
    const preview = await compileDefinitionFile(previewDefinitionPath);
    const portInputs = records(findInput(records(preview.module.inputs), "ports").item_inputs);

    assert.deepEqual(findInput(portInputs, "domains").patterns, findInput(records(ingress.module.inputs), "domains").patterns);
    assert.equal(findInput(portInputs, "domains").placeholder, findInput(records(ingress.module.inputs), "domains").placeholder);
  });

  it("picks the sandbox hosts' security groups from the network's and hands them to Terraform", async () => {
    const definition = await compileDefinitionFile(ingressDefinitionPath);
    const groups = findInput(records(definition.module.inputs), "sandbox_host_security_group_ids");

    assert.equal(groups.type, "string_array");
    assert.equal(groups.required, true);
    assert.equal(
      groups.values,
      "$values:aws/security-groups?awsAccountId=<<module.input.aws_account_id>>&region=<<module.input.aws_region>>&vpcId=<<module.input.vpc_id>>",
    );
    assert.equal(
      terraformVariables(definition.module).sandbox_host_security_groups,
      '<< map(uniq(module.input.sandbox_host_security_group_ids), {"name": #, "id": #}) >>',
    );
  });

  it("declares the outputs the new resources publish", async () => {
    const definition = await compileDefinitionFile(ingressDefinitionPath);
    const outputs = records(definition.module.outputs);
    const outputsFile = await readFile(resolve(repoRoot, "networking/preview_ingress/outputs.tf"), "utf8");

    for (const [id, type] of [
      ["sandbox_host_security_group_ids", "string_array"],
      ["custom_domain_names", "string_array"],
      ["custom_certificate_arn", "string"],
    ]) {
      assert.equal(outputs.find((output) => output.id === id)?.type, type);
    }
    for (const output of outputs) {
      assert.ok(outputsFile.includes(`output "${String(output.id)}"`), `expected Terraform output ${String(output.id)}`);
    }
  });

  it("passes every new input to a Terraform variable of its own", async () => {
    const definition = await compileDefinitionFile(ingressDefinitionPath);
    const variables = terraformVariables(definition.module);
    const variablesFile = await readFile(resolve(repoRoot, "networking/preview_ingress/variables.tf"), "utf8");

    for (const name of Object.keys(variables).filter((key) => key !== "...overrides")) {
      assert.ok(variablesFile.includes(`variable "${name}"`), `expected Terraform variable ${name}`);
    }
  });
});
