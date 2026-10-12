import assert from "node:assert/strict";
import { resolve } from "node:path";
import { it } from "node:test";
import { compileDefinitionFile } from "../src/compiler.js";

function record(value: unknown): Record<string, unknown> {
  assert.ok(value !== null && typeof value === "object" && !Array.isArray(value));
  return Object.fromEntries(Object.entries(value));
}

it("CloudFront defaults to viewer country forwarding and retains explicit origin policies", async () => {
  const definition = await compileDefinitionFile(resolve(process.cwd(), "../../cdn/cloudfront/rvn-cloudfront-definition.yml"));
  assert.ok(Array.isArray(definition.module.inputs));
  const policy = definition.module.inputs.map(record).find(input => input.id === "origin_request_policy");
  assert.ok(policy);
  assert.equal(policy.default, "33f36d7e-f396-46d9-90e0-52428a34d9dc");
  assert.ok(Array.isArray(policy.values));
  const values = policy.values.map(record);
  assert.ok(values.some(option => option.value === policy.default && String(option.label).includes("recommended")));
  assert.ok(values.some(option => option.value === "none"));
  assert.ok(values.some(option => option.value === "216adef6-5c7f-47e4-b989-5492eafa07d3"));
  assert.ok(values.some(option => option.value === "custom"));

  const stack = record(definition.module.stack);
  const defaults = record(record(stack.pipelines).defaults);
  const variables = record(record(defaults.input).terraform_variables);
  const behavior = record(variables.default_cache_behavior);
  assert.equal(behavior.origin_request_policy_id, '<< module.input.origin_request_policy == "custom" ? module.input.origin_request_policy_custom_id : module.input.origin_request_policy == "none" ? nil : module.input.origin_request_policy >>');
});
