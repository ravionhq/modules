import assert from "node:assert/strict";
import { resolve } from "node:path";
import { describe, it } from "node:test";
import { compileDefinitionFile } from "../src/compiler.js";

function record(value: unknown): Record<string, unknown> {
  assert.ok(value !== null && typeof value === "object" && !Array.isArray(value));
  return Object.fromEntries(Object.entries(value));
}

describe("ECS early success module definitions", () => {
  for (const type of ["web", "worker", "nlb"]) {
    it(`${type} exposes defaults and preserves the availability floor independently`, async () => {
      const definition = await compileDefinitionFile(resolve(process.cwd(), `../../compute/ecs_service/rvn-ecs-${type}-definition.yml`));
      const inputs = definition.module.inputs;
      assert.ok(Array.isArray(inputs));
      const fields = inputs.map(record);
      const healthy = fields.find(field => field.id === "deployment_success_healthy_percent");
      const cleanup = fields.find(field => field.id === "deployment_wait_for_drain");
      const floor = fields.find(field => field.id === "deployment_minimum_healthy_percent");
      assert.ok(healthy && cleanup && floor);
      assert.equal(healthy.default, 100);
      assert.equal(healthy.min, "<< module.input.deployment_minimum_healthy_percent >>");
      assert.equal(healthy.max, 100);
      assert.equal(cleanup.type, "boolean");
      assert.equal(cleanup.default, false);
      assert.equal(floor.default, 100);
      assert.deepEqual(healthy.show_when, type === "web" ? { deployment_strategy: "rolling" } : undefined);
      assert.deepEqual(cleanup.show_when, healthy.show_when);
      const strategy = record(definition.module.deploy).strategy;
      if (type === "web") {
        assert.equal(typeof strategy, "string");
        assert.match(String(strategy), /deployment_strategy == "rolling" \? \{/);
        assert.match(String(strategy), /deployment_success_healthy_percent != nil \? module.input.deployment_success_healthy_percent : 100/);
        assert.match(String(strategy), /deployment_wait_for_drain \? "BLOCKING" : "DEFERRED"/);
      } else {
        const rolling = record(strategy);
        const criteria = record(rolling.early_success_criteria);
        assert.equal(rolling.type, "rolling");
        assert.equal(rolling.minimum_healthy_percent, "<< module.input.deployment_minimum_healthy_percent != nil ? module.input.deployment_minimum_healthy_percent : 100 >>");
        assert.equal(criteria.healthy_percent, "<< module.input.deployment_success_healthy_percent != nil ? module.input.deployment_success_healthy_percent : 100 >>");
        assert.equal(criteria.source_service_revision_cleanup, '<< module.input.deployment_wait_for_drain ? "BLOCKING" : "DEFERRED" >>');
      }
    });
  }
});
