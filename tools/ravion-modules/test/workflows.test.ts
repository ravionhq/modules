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
    push: { branches: ["main", "ravion/merge-queue/**"] },
  });

  const jobs = workflow.jobs as Record<string, { permissions?: Record<string, string>; steps: Array<Record<string, unknown>> }>;
  assert.ok(jobs.validate);
  assert.ok(jobs["publish-plan"]);
  assert.ok(jobs.publish);
  assert.deepEqual(jobs["publish-plan"].permissions, { contents: "read", issues: "write", "pull-requests": "write" });
  assert.deepEqual(jobs.publish.permissions, { contents: "write" });
  assert.ok(jobs.validate.steps.some((step) => step.run === "node tools/ravion-modules/dist/src/cli.js guardrails"));
  assert.ok(jobs.validate.steps.some((step) => step.run === "node tools/ravion-modules/dist/src/cli.js compile"));
  assert.ok(jobs.validate.steps.some((step) => step.run === "node tools/ravion-modules/dist/src/cli.js readme --check"));
  assert.ok(jobs["publish-plan"].steps.some((step) => step.run === "node tools/ravion-modules/dist/src/cli.js publish --format markdown --output publish-plan.md 2> publish-plan.err"));
  assert.ok(jobs["publish-plan"].steps.some((step) => typeof step.run === "string" && step.run.includes("git diff --no-ext-diff") && step.run.includes("module-categories.ts")));
  assert.ok(jobs["publish-plan"].steps.some((step) => typeof step.with === "object" && JSON.stringify(step.with).includes("category-diff.md")));
  assert.ok(jobs["publish-plan"].steps.some((step) => step.run === "node tools/ravion-modules/dist/src/cli.js version-dry-run"));
  assert.ok(jobs.publish.steps.some((step) => step.run === "node tools/ravion-modules/dist/src/cli.js tags --api --create --overwrite > release-tags.json"));
  assert.ok(jobs.publish.steps.some((step) => step.run === "node tools/ravion-modules/dist/src/cli.js push-tags --plan release-tags.json"));
  assert.ok(jobs.publish.steps.some((step) => step.run === "node tools/ravion-modules/dist/src/cli.js publish --apply"));
  assert.ok(jobs.publish.steps.some((step) => step.run === "node tools/ravion-modules/dist/src/cli.js github-releases --plan release-tags.json --create"));
  assert.ok(jobs.publish.steps.some((step) => step.run === "node tools/ravion-modules/dist/src/cli.js readme"));
  assert.ok(jobs.publish.steps.some((step) => typeof step.run === "string" && step.run.includes("git push origin HEAD:main")));
});

type WorkflowJob = {
  name?: string;
  if?: string;
  needs?: string | string[];
  steps?: Array<Record<string, unknown>>;
};
type Workflow = {
  on: Record<string, { branches?: string[] }>;
  concurrency?: { group: string; "cancel-in-progress"?: unknown };
  jobs: Record<string, WorkflowJob>;
};

async function loadWorkflow(file: string): Promise<Workflow> {
  return YAML.parse(await readFile(resolve("../../.github/workflows", file), "utf8")) as Workflow;
}

// Minimal evaluator for the job `if:` expressions used in these workflows.
function evaluateIf(expression: string | undefined, context: { eventName: string; ref: string; fork?: boolean }): boolean {
  if (expression === undefined) return true;
  let expr = expression.trim();
  if (expr.startsWith("${{") && expr.endsWith("}}")) expr = expr.slice(3, -2);
  if (/^\s*always\(\)\s*$/.test(expr)) return true;
  const js = expr
    .replace(/github\.event\.pull_request\.head\.repo\.fork/g, JSON.stringify(context.fork ?? false))
    .replace(/github\.event_name/g, JSON.stringify(context.eventName))
    .replace(/github\.ref/g, JSON.stringify(context.ref))
    .replace(/startsWith\(/g, "__startsWith(")
    .replace(/'/g, '"');
  assert.match(js, /^[\s\w"/.*()|&=!,-]+$/, `unexpected expression: ${expression}`);
  return Boolean(new Function("__startsWith", `return (${js});`)((value: string, prefix: string) => value.startsWith(prefix)));
}

const candidatePush = { eventName: "push", ref: "refs/heads/ravion/merge-queue/mqcand_abc123/760effde0123456789" };
const mainPush = { eventName: "push", ref: "refs/heads/main" };
const otherPush = { eventName: "push", ref: "refs/heads/feature/x" };
const pullRequest = { eventName: "pull_request", ref: "refs/pull/1/merge" };

const requiredChecks: Array<[string, string]> = [
  ["module-definitions.yml", "Validate Module Definitions"],
  ["terraform-static-checks.yml", "Validate Terraform Modules"],
  ["module-definitions.yml", "Publish Dry-Run Plan"],
];

test("required check workflows run on merge queue candidate pushes", async () => {
  for (const file of new Set(requiredChecks.map(([workflowFile]) => workflowFile))) {
    const workflow = await loadWorkflow(file);
    assert.deepEqual(workflow.on.push?.branches, ["main", "ravion/merge-queue/**"], file);
    assert.equal((workflow.on.push as Record<string, unknown>).paths, undefined, `${file} must not path-filter candidate pushes`);
    assert.deepEqual(workflow.on.pull_request?.branches, ["main"], file);
  }
});

test("every required check runs on merge queue candidate pushes", async () => {
  for (const [file, checkName] of requiredChecks) {
    const workflow = await loadWorkflow(file);
    const entry = Object.entries(workflow.jobs).find(([, job]) => job.name === checkName);
    assert.ok(entry, `${checkName} not found in ${file}`);
    const [, job] = entry;
    assert.equal(evaluateIf(job.if, candidatePush), true, `${checkName} must run on candidate pushes`);
    assert.equal(evaluateIf(job.if, { ...pullRequest, fork: false }), true, `${checkName} must run on pull requests`);
    // Its dependencies must also run, otherwise the check is skipped.
    const needs = job.needs === undefined ? [] : Array.isArray(job.needs) ? job.needs : [job.needs];
    for (const need of needs) {
      assert.equal(evaluateIf(workflow.jobs[need]?.if, candidatePush), true, `${need} (needed by ${checkName}) must run on candidate pushes`);
    }
  }
});

test("publish dry-run plan skips PR-only steps on candidate pushes and never runs on main", async () => {
  const workflow = await loadWorkflow("module-definitions.yml");
  const plan = workflow.jobs["publish-plan"];
  assert.equal(evaluateIf(plan.if, mainPush), false);
  assert.equal(evaluateIf(plan.if, otherPush), false);
  assert.equal(evaluateIf(plan.if, { ...pullRequest, fork: true }), false);
  const step = (name: string) => plan.steps?.find((candidate) => candidate.name === name);
  assert.match(String(step("Comment publish dry-run plan")?.if), /github\.event_name == 'pull_request'/);
  assert.match(String(step("Generate module category source diff")?.if), /github\.event_name == 'pull_request'/);
  assert.equal(step("Fail when publish dry-run plan failed")?.if, "steps.publish_plan.outcome == 'failure'");
});

test("side-effecting jobs only run for pushes to main", async () => {
  const workflow = await loadWorkflow("module-definitions.yml");
  const publish = workflow.jobs.publish;
  assert.equal(publish.name, "Publish Module Definitions");
  assert.match(String(publish.if), /github\.ref == 'refs\/heads\/main'/);
  assert.equal(evaluateIf(publish.if, mainPush), true);
  assert.equal(evaluateIf(publish.if, candidatePush), false);
  assert.equal(evaluateIf(publish.if, otherPush), false);
  assert.equal(evaluateIf(publish.if, pullRequest), false);
});

test("candidate runs do not share concurrency groups with main runs", async () => {
  const definitions = await loadWorkflow("module-definitions.yml");
  // Pushes fall back to the unique run id, so no push run is ever cancelled.
  assert.equal(definitions.concurrency?.group, "${{ github.workflow }}-${{ github.event.pull_request.number || github.run_id }}");
  assert.equal(definitions.concurrency?.["cancel-in-progress"], "${{ github.event_name == 'pull_request' }}");

  const terraform = await loadWorkflow("terraform-static-checks.yml");
  // Pushes group by ref; every candidate has its own ref, distinct from main.
  assert.equal(terraform.concurrency?.group, "${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}");
});
