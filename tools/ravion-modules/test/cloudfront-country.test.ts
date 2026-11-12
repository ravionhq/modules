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

it("CloudFront exposes primary origin connection and response timeouts", async () => {
  const definition = await compileDefinitionFile(resolve(process.cwd(), "../../cdn/cloudfront/rvn-cloudfront-definition.yml"));
  assert.ok(Array.isArray(definition.module.inputs));
  const inputs = definition.module.inputs.map(record);
  const expected: Record<string, [number, number, number]> = {
    origin_connection_timeout: [1, 10, 10],
    origin_connection_attempts: [1, 3, 3],
    origin_read_timeout: [1, 180, 30],
    origin_keepalive_timeout: [1, 180, 5],
  };
  for (const [id, [min, max, defaultValue]] of Object.entries(expected)) {
    const input = inputs.find(candidate => candidate.id === id);
    assert.ok(input, id);
    assert.equal(input.type, "number");
    assert.equal(input.min, min);
    assert.equal(input.max, max);
    assert.equal(input.default, defaultValue);
    assert.equal(input.collapsible, true, id);
  }

  const stack = record(definition.module.stack);
  const defaults = record(record(stack.pipelines).defaults);
  const origins = String(record(record(defaults.input).terraform_variables).origins);
  assert.match(origins, /"connection_timeout": module\.input\.origin_connection_timeout/);
  assert.match(origins, /"connection_attempts":\s+module\.input\.origin_connection_attempts/);
  assert.match(origins, /"origin_read_timeout": \(module\.input\.origin_source ==\s+"s3_bucket" \? nil : module\.input\.origin_read_timeout\)/);
  assert.match(origins, /"origin_keepalive_timeout":\s+\(module\.input\.origin_source == "s3_bucket" \? nil : module\.input\.origin_keepalive_timeout\)/);
});
