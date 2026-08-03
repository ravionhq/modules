import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import test from "node:test";
import YAML from "yaml";

test("module definition workflow has valid syntax and expected jobs", async () => {
  const workflowPath = resolve("../../.github/workflows/module-definitions.yml");
  const workflow = YAML.parse(await readFile(workflowPath, "utf8")) as Record<string, unknown>;

  assert.equal(workflow.name, "Module Definitions");
  assert.deepEqual(workflow.on, {
    pull_request: { branches: ["main"] },
    push: { branches: ["main"] },
  });

  const jobs = workflow.jobs as Record<string, { permissions?: Record<string, string>; steps: Array<Record<string, unknown>> }>;
  assert.ok(jobs.validate);
  assert.ok(jobs["publish-plan"]);
  assert.ok(jobs.publish);
  assert.deepEqual(jobs["publish-plan"].permissions, { contents: "read", issues: "write", "pull-requests": "write" });
  assert.deepEqual(jobs.publish.permissions, { contents: "write" });
  assert.ok(jobs.validate.steps.some((step) => step.run === "node tools/ravion-modules/dist/src/cli.js guardrails"));
  assert.ok(jobs.validate.steps.some((step) => step.run === "node tools/ravion-modules/dist/src/cli.js compile"));
  assert.ok(jobs["publish-plan"].steps.some((step) => step.run === "node tools/ravion-modules/dist/src/cli.js publish --validate-remote --format markdown --output publish-plan.md 2> publish-plan.err"));
  assert.ok(jobs.publish.steps.some((step) => step.run === "node tools/ravion-modules/dist/src/cli.js publish --validate-remote"));
  assert.ok(jobs.publish.steps.some((step) => step.run === "node tools/ravion-modules/dist/src/cli.js tags --api --create --overwrite > release-tags.json"));
  assert.ok(jobs.publish.steps.some((step) => step.run === "node tools/ravion-modules/dist/src/cli.js push-tags --plan release-tags.json"));
  assert.ok(jobs.publish.steps.some((step) => step.run === "node tools/ravion-modules/dist/src/cli.js publish --apply"));
  assert.ok(jobs.publish.steps.some((step) => step.run === "node tools/ravion-modules/dist/src/cli.js github-releases --plan release-tags.json --create"));
});
