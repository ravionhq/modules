import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { it } from "node:test";
import YAML from "yaml";
import { compileDefinitionFile } from "../src/compiler.js";

const modulePath = resolve(process.cwd(), "../../database/planetscale_vitess");

function record(value: unknown): Record<string, unknown> {
  assert.ok(value && typeof value === "object" && !Array.isArray(value));
  return value as Record<string, unknown>;
}

it("wires the MySQL definition to a two-stage pipeline with runner-only credentials", async () => {
  const compiled = await compileDefinitionFile(`${modulePath}/rvn-planetscale-vitess-definition.yml`);
  const stack = record(compiled.module.stack);
  const pipelines = record(stack.pipelines);
  const defaults = record(record(pipelines.defaults).input);
  assert.equal(record(pipelines.change).pipeline_id, "<< module.input.change_pipeline_id >>");
  assert.equal(record(pipelines.destroy).pipeline_id, "<< defaults.destroy_pipeline_id >>");
  assert.equal(defaults.ref, `rvn-planetscale-vitess@${compiled.version}`);
  assert.equal(defaults.base_path, "database/planetscale_vitess");

  const variables = record(defaults.terraform_variables);
  assert.equal(variables["...overrides"], "<< module.input.advanced_terraform_variables >>");
  assert.equal("service_token" in variables, false);
  assert.equal("service_token_id" in variables, false);
  const credentials = record(defaults.environment_variables);
  for (const [name, key] of [["PLANETSCALE_SERVICE_TOKEN", "service_token"], ["PLANETSCALE_SERVICE_TOKEN_ID", "service_token_id"]]) {
    const secret = record(record(credentials[name]).from_secrets_manager);
    assert.equal(secret.json_key, key);
    assert.equal(secret.key, "<< module.input.service_token_secret >>");
  }

  const config = record(YAML.parse(await readFile(`${modulePath}/pipelines/change.yml`, "utf8")));
  assert.ok(Array.isArray(config.inputs));
  const declaredInputs = new Set(config.inputs.map((input: unknown) => record(input).id));
  assert.ok(Object.keys(defaults).every((key) => declaredInputs.has(key)), "Every module pipeline input must be declared");
  assert.ok(Array.isArray(config.steps));
  const group = record(config.steps[0]);
  assert.deepEqual(group.concurrency, {
    key: "<< pipeline.input.stack_id >>", scope: "organization", value: 1, behavior: "queue",
  });
  assert.ok(Array.isArray(group.steps));
  const steps = group.steps.map(record);
  assert.deepEqual(steps.map((step) => step.id), [
    "bootstrap_plan", "bootstrap_approve", "bootstrap_apply", "plan", "approve", "apply",
  ]);
  const [bootstrap, , bootstrapApply, plan, , apply] = steps;
  assert.deepEqual(bootstrap.source, plan.source);
  assert.equal(bootstrap.stack_id, plan.stack_id);
  assert.equal(bootstrap.terraform_variables, plan.terraform_variables);
  assert.equal(record(bootstrap.environment_variables).TF_CLI_ARGS_plan, "-target=planetscale_vitess_branch.main");
  assert.equal(plan.environment_variables, "<< pipeline.input.environment_variables >>");
  assert.equal(bootstrapApply.plan_file_uri, "<< steps.bootstrap_plan.output.plan_file_uri >>");
  assert.equal(apply.plan_file_uri, "<< steps.plan.output.plan_file_uri >>");
  // Nested admission to the same key would deadlock while the group holds it.
  assert.ok(steps.every((step) => !("concurrency" in step)));
});
