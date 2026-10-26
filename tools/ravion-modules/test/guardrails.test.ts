import assert from "node:assert/strict";
import { mkdtemp, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";
import { compileAllDefinitions } from "../src/compiler.js";
import { GuardrailError, runMigrationGuardrails } from "../src/guardrails.js";

describe("migration guardrails", () => {
  it("fails when legacy module definition YAML files are added", async () => {
    const rootPath = await mkdtemp(join(tmpdir(), "ravion-legacy-"));
    await mkdir(join(rootPath, "modules"), { recursive: true });
    await writeFile(
      join(rootPath, "modules", "ravion-aws-vpc.yml"),
      ["type: ravion-aws-vpc", "name: AWS VPC", "inputs: []", ""].join("\n"),
    );

    await assert.rejects(
      runMigrationGuardrails(rootPath),
      (error) => error instanceof GuardrailError && error.message.includes("Legacy module definition YAML files") && error.message.includes("ravion-aws-vpc.yml"),
    );
  });

  it("allows typed colocated definition files beside Terraform modules", async () => {
    const rootPath = await mkdtemp(join(tmpdir(), "ravion-colocated-"));
    await mkdir(join(rootPath, "networking", "vpc"), { recursive: true });
    await mkdir(join(rootPath, "containers", "ecr"), { recursive: true });
    await writeFile(
      join(rootPath, "networking", "vpc", "ravion-aws-vpc-definition.yml"),
      ["definition:", "  type: ravion-aws-vpc", "  name: AWS VPC", "module: {}", ""].join("\n"),
    );
    await writeFile(
      join(rootPath, "containers", "ecr", "rvn-aws-ecr-definition.yml"),
      ["definition:", "  type: rvn-aws-ecr", "  name: AWS ECR Repository", "module: {}", ""].join("\n"),
    );

    await assert.doesNotReject(runMigrationGuardrails(rootPath));
  });

  it("rejects old colocated definition.yml files", async () => {
    const rootPath = await mkdtemp(join(tmpdir(), "ravion-old-colocated-"));
    await mkdir(join(rootPath, "networking", "vpc"), { recursive: true });
    await writeFile(
      join(rootPath, "networking", "vpc", "definition.yml"),
      ["definition:", "  type: ravion-aws-vpc", "  name: AWS VPC", "module: {}", ""].join("\n"),
    );

    await assert.rejects(
      runMigrationGuardrails(rootPath),
      (error) => error instanceof GuardrailError && error.message.includes("Legacy module definition YAML files") && error.message.includes("definition.yml"),
    );
  });

  it("fails on duplicate definition.type values", async () => {
    const rootPath = await mkdtemp(join(tmpdir(), "ravion-duplicate-"));
    await writeDefinition(rootPath, "networking", "vpc", "ravion-aws-network");
    await writeDefinition(rootPath, "compute", "cluster", "ravion-aws-network");

    await assert.rejects(
      compileAllDefinitions(rootPath),
      (error) => error instanceof GuardrailError && error.message.includes("Duplicate definition.type") && error.message.includes("ravion-aws-network"),
    );
  });
});

async function writeDefinition(rootPath: string, category: string, moduleName: string, type: string): Promise<void> {
  const modulePath = join(rootPath, category, moduleName);
  await mkdir(modulePath, { recursive: true });
  await writeFile(
    join(modulePath, `${type}-definition.yml`),
    [
      "definition:",
      `  type: ${type}`,
      `  name: ${type}`,
      "  description: Test module",
      "release:",
      "  version: 1.0.0",
      "  description: Initial release.",
      "module:",
      "  inputs: []",
      "",
    ].join("\n"),
  );
}
