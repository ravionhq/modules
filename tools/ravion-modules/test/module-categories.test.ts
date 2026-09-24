import assert from "node:assert/strict";
import { resolve } from "node:path";
import { describe, it } from "node:test";
import { compileAllDefinitions } from "../src/compiler.js";
import {
  getModuleCategoriesForDefinitionType,
  MODULE_CATEGORIES,
} from "../src/module-categories.js";

const repoRoot = resolve(process.cwd(), "../..");

describe("module categories", () => {
  it("assigns every authored module definition to at least one category", async () => {
    const definitions = await compileAllDefinitions(repoRoot);
    const assignments = MODULE_CATEGORIES.flatMap((category) =>
      category.definitionTypes.map((definitionType) => `${category.givenId}:${definitionType}`),
    );

    assert.equal(new Set(assignments).size, assignments.length);
    assert.deepEqual(
      definitions
        .filter((definition) => getModuleCategoriesForDefinitionType(definition.type).length === 0)
        .map((definition) => definition.type),
      [],
    );
  });

  it("cross-lists general-purpose server modules by workload intent", () => {
    assert.deepEqual(
      getModuleCategoriesForDefinitionType("rvn-ec2-service").map((category) => category.givenId),
      ["web-server", "worker"],
    );
    assert.deepEqual(
      getModuleCategoriesForDefinitionType("rvn-ecs-nlb").map((category) => category.givenId),
      ["web-server", "tcp-udp-server"],
    );
    assert.deepEqual(
      getModuleCategoriesForDefinitionType("rvn-eks-web").map((category) => category.givenId),
      ["web-server"],
    );
    assert.deepEqual(
      getModuleCategoriesForDefinitionType("rvn-eks-cron").map((category) => category.givenId),
      ["worker"],
    );
    assert.deepEqual(
      getModuleCategoriesForDefinitionType("rvn-eks-worker").map((category) => category.givenId),
      ["worker"],
    );
  });

  it("groups EKS infrastructure definitions with clusters", () => {
    for (const definitionType of ["rvn-eks-cluster", "rvn-eks-addons"]) {
      assert.deepEqual(
        getModuleCategoriesForDefinitionType(definitionType).map((category) => category.givenId),
        ["cluster"],
      );
    }
  });
});
