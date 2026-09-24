import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";
import { compileDefinitionFile } from "../src/compiler.js";
import {
  generateDefinitionsFromInventory,
  normalizeRemoteConfigForComparison,
  type RemoteModuleInventory,
} from "../src/generate-definitions.js";

describe("definition generation", () => {
  it("generates self-contained colocated definitions for matching rvn modules", async () => {
    const rootPath = await createModuleRoot(["networking/vpc"]);
    const inventory = createInventory();

    const result = await generateDefinitionsFromInventory(inventory, rootPath, { write: true });

    assert.deepEqual(result.missing, [
      { type: "rvn-missing", expectedModulePath: undefined, reason: "No matching Terraform module directory exists." },
    ]);
    assert.equal(result.generated.length, 1);
    assert.equal(result.generated[0].modulePath, "networking/vpc");

    const content = await readFile(join(rootPath, "networking", "vpc", "rvn-aws-network-definition.yml"), "utf8");
    assert.match(content, /type: rvn-aws-network/);
    assert.match(content, /ref: \$local\.module_tag/);
    assert.doesNotMatch(content, /\$include|\$merge|\$template/);

    const compiled = await compileDefinitionFile(join(rootPath, "networking", "vpc", "rvn-aws-network-definition.yml"));
    assert.deepEqual(
      compiled.module,
      normalizeRemoteConfigForComparison(inventory.versionsByDefinitionId.network[0].config, "rvn-aws-network", "1.2.0", "networking/vpc"),
    );
  });

  it("selects the latest remote version", async () => {
    const rootPath = await createModuleRoot(["networking/vpc"]);
    const inventory = createInventory();
    inventory.versionsByDefinitionId.network.push({
      moduleDefinitionId: "network",
      version: "1.3.0",
      description: "Latest VPC definition.",
      config: { inputs: [{ id: "name", type: "string", label: "Name" }] },
    });

    const result = await generateDefinitionsFromInventory(inventory, rootPath);

    assert.equal(result.generated[0].version, "1.3.0");
    assert.match(result.generated[0].content, /version: 1\.3\.0/);
  });

  it("selects stable releases over prereleases with the same version core", async () => {
    const rootPath = await createModuleRoot(["networking/vpc"]);
    const inventory = createInventory();
    inventory.versionsByDefinitionId.network.unshift({
      moduleDefinitionId: "network",
      version: "1.2.0-alpha",
      description: "Prerelease VPC definition.",
      config: { inputs: [{ id: "name", type: "string", label: "Name" }] },
    });

    const result = await generateDefinitionsFromInventory(inventory, rootPath);

    assert.equal(result.generated[0].version, "1.2.0");
    assert.match(result.generated[0].content, /version: 1\.2\.0/);
  });

  it("generates stack-only definitions without Terraform files", async () => {
    const rootPath = await createModuleRoot([]);
    const stackPath = join(rootPath, "stack", "terraform");
    await mkdir(stackPath, { recursive: true });
    await writeFile(join(stackPath, "rvn-stack-definition.yml"), "definition:\n  type: rvn-stack\n");
    const inventory = createInventory();
    inventory.definitions = [{ id: "stack", type: "rvn-stack", name: "Stack", description: "Terraform stack." }];
    inventory.versionsByDefinitionId = {
      stack: [{ moduleDefinitionId: "stack", version: "1.8.37", description: "Stack definition.", config: { inputs: [] } }],
    };

    const result = await generateDefinitionsFromInventory(inventory, rootPath);

    assert.deepEqual(result.missing, []);
    assert.equal(result.generated[0].modulePath, "stack/terraform");
  });
});

async function createModuleRoot(modulePaths: string[]): Promise<string> {
  const rootPath = await mkdtemp(join(tmpdir(), "ravion-modules-"));
  for (const modulePath of modulePaths) {
    const directoryPath = join(rootPath, modulePath);
    await mkdir(directoryPath, { recursive: true });
    await writeFile(join(directoryPath, "versions.tf"), "terraform {}\n");
  }
  return rootPath;
}

function createInventory(): RemoteModuleInventory {
  return {
    definitions: [
      {
        id: "network",
        type: "rvn-aws-network",
        name: "VPC Network",
        description: "Production-ready AWS VPC.",
      },
      {
        id: "missing",
        type: "rvn-missing",
        name: "Missing",
        description: "No Terraform module exists.",
      },
      {
        id: "custom",
        type: "custom-module",
        name: "Custom",
        description: "Ignored because it is not rvn-prefixed.",
      },
    ],
    versionsByDefinitionId: {
      network: [
        {
          moduleDefinitionId: "network",
          version: "1.2.0",
          description: "Import VPC definition.",
          config: {
            inputs: [{ id: "name", type: "string", label: "Name", applied_by: [] }],
            stack: {
              type: "opentofu",
              source: {
                repo: "https://github.com/ravionhq/modules",
                ref: "abc123",
                base_path: "networking/vpc",
              },
              pipelines: {
                defaults: {
                  input: {
                    repo: "https://github.com/ravionhq/modules",
                    ref: "abc123",
                    base_path: "networking/vpc",
                  },
                },
              },
            },
          },
        },
      ],
      missing: [
        {
          moduleDefinitionId: "missing",
          version: "0.1.0",
          description: "Missing module.",
          config: { inputs: [] },
        },
      ],
    },
  };
}
