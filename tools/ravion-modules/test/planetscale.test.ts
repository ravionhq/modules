import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { it } from "node:test";
import { compileDefinitionFile } from "../src/compiler.js";

const modulePath = resolve(process.cwd(), "../../database/planetscale_vitess");

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function record(value: unknown): Record<string, unknown> {
  assert.ok(isRecord(value));
  return value;
}

it("uses standard pipelines and automatically adopts the default keyspace after creation", async () => {
  const compiled = await compileDefinitionFile(`${modulePath}/rvn-planetscale-vitess-definition.yml`);
  const pipelines = record(record(compiled.module.stack).pipelines);
  const defaults = record(record(pipelines.defaults).input);
  assert.equal(record(pipelines.change).pipeline_id, "<< defaults.change_pipeline_id >>");
  assert.equal(record(pipelines.destroy).pipeline_id, "<< defaults.destroy_pipeline_id >>");
  assert.equal(defaults.ref, `rvn-planetscale-vitess@${compiled.version}`);
  assert.equal(defaults.base_path, "database/planetscale_vitess");
  assert.deepEqual(defaults.integrations, ["<< module.input.planetscale >>"]);
  assert.equal(defaults.timeout, 2700);

  const variables = record(defaults.terraform_variables);
  assert.equal(variables["...overrides"], "<< module.input.advanced_terraform_variables >>");
  assert.equal(variables.manage_default_keyspace, '<< stack.output && stack.output["branch_id"] ? true : false >>');
  assert.equal("service_token" in variables, false);
  assert.equal("service_token_id" in variables, false);
  assert.equal("organization" in variables, false, "Organization comes from the selected integration");
  assert.equal(variables.extra_replicas, "<< module.input.extra_replicas >>");
  assert.equal(record(variables.application_password).cidrs, "<< module.input.application_password_cidrs >>");
  assert.equal("environment_variables" in defaults, false, "Runner injects short-lived credentials");

  assert.ok(Array.isArray(compiled.module.inputs));
  const inputs = compiled.module.inputs.map(record);
  for (const id of ["extra_replicas", "application_password_cidrs"]) {
    assert.ok(inputs.some((input) => input.id === id), `${id} must be configurable in the form`);
  }
  assert.ok(inputs.every((input) => ![
    "organization", "service_token_secret", "change_pipeline_id", "destroy_pipeline_id", "manage_default_keyspace",
  ].includes(String(input.id))), "No manual credentials, custom pipeline, or adoption switch in the form");

  const connection = inputs.find((input) => input.id === "planetscale");
  assert.ok(connection);
  assert.equal(connection.type, "string");
  assert.equal(connection.values, "$values:ravion/integrations?provider=PLANETSCALE");
  assert.equal(connection.required, true);
  assert.equal(connection.immutable, true);
  const region = inputs.find((input) => input.id === "region");
  assert.ok(region);
  assert.equal(region.values, "$values:planetscale/regions?integrationId=<< module.input.planetscale >>");
  assert.equal(region.required, true);
  assert.equal(region.immutable, true);
  const size = inputs.find((input) => input.id === "cluster_size");
  assert.ok(size);
  assert.equal(size.values, "$values:planetscale/cluster-sizes?integrationId=<< module.input.planetscale >>&region=<< module.input.region >>");
  assert.equal(size.default, "PS_10");
  assert.equal(size.required, true);
});

it("matches RDS and Aurora Terraform settings and standard change/destroy pipeline defaults", async () => {
  const definitions = await Promise.all([
    "planetscale_vitess/rvn-planetscale-vitess-definition.yml",
    "rds/rvn-rds-definition.yml",
    "aurora/rvn-aurora-definition.yml",
  ].map((file) => compileDefinitionFile(resolve(modulePath, "..", file))));
  const settingsIds = [
    "section_advanced", "opentofu_version", "ravion_state_backend_workspace", "advanced_terraform_variables",
  ];
  const reference = definitions[0];
  assert.ok(reference);
  assert.ok(Array.isArray(reference.module.inputs));
  const settings = reference.module.inputs.map(record).filter((input) => settingsIds.includes(String(input.id)));
  assert.equal(settings.length, settingsIds.length);
  const referencePipelines = record(record(reference.module.stack).pipelines);
  const referenceDefaults = record(record(referencePipelines.defaults).input);

  for (const definition of definitions.slice(1)) {
    assert.ok(Array.isArray(definition.module.inputs));
    assert.deepEqual(
      definition.module.inputs.map(record).filter((input) => settingsIds.includes(String(input.id))),
      settings,
      `${definition.type} and PlanetScale must use identical shared Terraform settings`,
    );
    const pipelines = record(record(definition.module.stack).pipelines);
    assert.deepEqual(pipelines.change, referencePipelines.change);
    assert.deepEqual(pipelines.destroy, referencePipelines.destroy);
    const defaults = record(record(pipelines.defaults).input);
    assert.equal(defaults.tool_version, referenceDefaults.tool_version);
    assert.equal(defaults.execution_environment_id, referenceDefaults.execution_environment_id);
    assert.equal(
      record(defaults.terraform_variables)["...overrides"],
      record(referenceDefaults.terraform_variables)["...overrides"],
    );
  }
});

it("keeps the official provider and protects branch identity during keyspace resize", async () => {
  const [versions, branch, keyspace, data, outputs] = await Promise.all([
    "versions.tf", "vitess_branch.tf", "vitess_keyspace.tf", "data.tf", "outputs.tf",
  ].map((file) => readFile(`${modulePath}/${file}`, "utf8")));
  assert.match(versions, /source\s*=\s*"planetscale\/planetscale"/);
  assert.match(branch, /ignore_changes\s*=\s*\[cluster_size\]/);
  assert.match(keyspace, /for_each\s*=\s*var\.manage_default_keyspace \? \{ main = true \} : \{\}/);
  assert.match(keyspace, /count\s*=\s*var\.manage_default_keyspace \? 1 : 0/);
  assert.match(keyspace, /moved\s*\{\s*from = planetscale_vitess_keyspace\.main\s*to\s*= planetscale_vitess_keyspace\.main\[0\]/);
  assert.match(data, /data "planetscale_vitess_keyspaces" "main"\s*\{[\s\S]*database\s*=\s*var\.name[\s\S]*branch\s*=\s*"main"/);
  assert.match(outputs, /output "branch_id"/);
  assert.match(outputs, /output "default_keyspace_managed"/);
});
