import assert from "node:assert/strict";
import { join } from "node:path";
import { describe, it } from "node:test";
import { type CompiledDefinition } from "../src/compiler.js";
import { type RemoteModuleInventory } from "../src/generate-definitions.js";
import { getReleaseStatuses, ReleaseMetadataError, validateReleaseStatuses } from "../src/release.js";

describe("release metadata", () => {
  it("reports local release versions and unpublished remote state", () => {
    const statuses = getReleaseStatuses([createCompiledDefinition()], {
      inventory: { definitions: [], versionsByDefinitionId: {} },
      rootPath: "/repo",
    });

    assert.deepEqual(statuses.map(({ type, version, releaseDescription, modulePath, publishState }) => ({ type, version, releaseDescription, modulePath, publishState })), [
      {
        type: "ravion-aws-vpc",
        version: "1.2.3",
        releaseDescription: "Add subnet options.",
        modulePath: "networking/vpc",
        publishState: "unpublished",
      },
    ]);
  });

  it("reports published state when the remote version config matches", () => {
    const statuses = getReleaseStatuses([createCompiledDefinition()], { inventory: createInventory({ inputs: [{ label: "Name", type: "string", id: "name" }] }) });

    assert.equal(statuses[0].publishState, "published");
  });

  it("rejects remote versions with different compiled config", () => {
    const statuses = getReleaseStatuses([createCompiledDefinition()], { inventory: createInventory({ inputs: [{ id: "region", type: "string", label: "Region" }] }) });

    assert.throws(
      () => validateReleaseStatuses(statuses),
      (error) => error instanceof ReleaseMetadataError && error.message.includes("ravion-aws-vpc@1.2.3"),
    );
  });

  it("rejects unpublished versions without a release description", () => {
    const statuses = getReleaseStatuses([{ ...createCompiledDefinition(), releaseDescription: " " }], {
      inventory: { definitions: [], versionsByDefinitionId: {} },
    });

    assert.throws(() => validateReleaseStatuses(statuses), (error) => error instanceof ReleaseMetadataError);
  });

  it("reports disabled publication without requiring release validation", () => {
    const statuses = getReleaseStatuses([{ ...createCompiledDefinition(), published: false, releaseDescription: " " }], {
      inventory: { definitions: [], versionsByDefinitionId: {} },
    });

    assert.equal(statuses[0].publishState, "disabled");
    assert.doesNotThrow(() => validateReleaseStatuses(statuses));
  });
});

function createCompiledDefinition(): CompiledDefinition {
  return {
    filePath: join("/repo", "networking", "vpc", "ravion-aws-vpc-definition.yml"),
    published: true,
    global: true,
    type: "ravion-aws-vpc",
    name: "AWS VPC",
    description: "AWS VPC and subnets.",
    version: "1.2.3",
    releaseDescription: "Add subnet options.",
    module: { inputs: [{ id: "name", type: "string", label: "Name" }] },
  };
}

function createInventory(config: Record<string, unknown>): RemoteModuleInventory {
  return {
    definitions: [{ id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." }],
    versionsByDefinitionId: {
      vpc: [{ moduleDefinitionId: "vpc", version: "1.2.3", description: "Add subnet options.", config }],
    },
  };
}
