import assert from "node:assert/strict";
import { resolve } from "node:path";
import { describe, it } from "node:test";
import { compileDefinitionFile } from "../src/compiler.js";

function record(value: unknown): Record<string, unknown> {
  assert.ok(value !== null && typeof value === "object" && !Array.isArray(value));
  return Object.fromEntries(Object.entries(value));
}

const modulesThatBuildFromGit = [
  "compute/ec2_service/rvn-ec2-service-definition.yml",
  "compute/ecs_service/rvn-ecs-web-definition.yml",
  "compute/ecs_service/rvn-ecs-nlb-definition.yml",
  "compute/ecs_service/rvn-ecs-worker-definition.yml",
  "compute/eks_service/rvn-eks-web-definition.yml",
  "compute/eks_service/rvn-eks-worker-definition.yml",
  "compute/eks_service/rvn-eks-cron-definition.yml",
  "compute/lambda/rvn-lambda-definition.yml",
  "hosting/static_site/rvn-aws-static-definition.yml",
];

describe("watch paths in modules that build from git", () => {
  for (const path of modulesThatBuildFromGit) {
    it(`${path} gates its build on the watch paths input`, async () => {
      const definition = await compileDefinitionFile(resolve(process.cwd(), "../..", path));
      const inputs = definition.module.inputs;
      assert.ok(Array.isArray(inputs));
      const fields = inputs.map(record);
      const watchPaths = fields.find(field => field.id === "watch_paths");
      const sourceRepo = fields.find(field => field.id === "source_repo");
      assert.ok(watchPaths, "the module has a watch_paths input");
      assert.ok(sourceRepo, "the module builds from a git repository");
      assert.equal(watchPaths.type, "string_array");
      assert.equal(watchPaths.required, undefined, "empty watch paths always build");
      assert.deepEqual(watchPaths.show_when, sourceRepo.show_when, "watch paths show whenever the git source does");
      assert.equal(record(definition.module.build).watch_paths, "<< module.input.watch_paths >>");
    });
  }
});
