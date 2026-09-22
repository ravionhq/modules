import assert from "node:assert/strict";
import { join } from "node:path";
import { describe, it } from "node:test";
import { type CompiledDefinition } from "../src/compiler.js";
import { type RemoteModuleDefinition, type RemoteModuleVersion } from "../src/generate-definitions.js";
import { MODULE_CATEGORIES } from "../src/module-categories.js";
import {
  createDefaultRavionApiClient,
  dryRunModuleVersions,
  formatPublishPlanMarkdown,
  PublishPlanError,
  publishDefinitions,
  PublishError,
  type ModuleCategoryInput,
  type ModuleCategoryPatchInput,
  type ModuleDefinitionInput,
  type ModuleDefinitionPatchInput,
  type ModuleVersionInput,
  type RavionModuleApiClient,
  type RemoteModuleCategory,
} from "../src/publish.js";

describe("publish", () => {
  it("skips definitions whose root publication setting is false", async () => {
    const client = new MockRavionClient();

    const result = await publishDefinitions([createCompiledDefinition({ published: false })], client, { dryRun: false });
    const dryRunResults = await dryRunModuleVersions([createCompiledDefinition({ published: false })], client);

    assert.deepEqual(result, { dryRun: false, categoryItems: [], items: [] });
    assert.deepEqual(dryRunResults, []);
    assert.deepEqual(client.createdCategories, []);
    assert.deepEqual(client.createdDefinitions, []);
    assert.deepEqual(client.createdVersions, []);
    assert.deepEqual(client.dryRunVersions, []);
  });

  it("creates missing definitions and versions through the Ravion API", async () => {
    const client = new MockRavionClient();

    const result = await publishDefinitions([createCompiledDefinition()], client, { dryRun: false });

    assert.deepEqual(result.items.map(({ action, dryRun }) => ({ action, dryRun })), [
      { action: "create-definition", dryRun: false },
      { action: "create-version", dryRun: false },
      { action: "patch-definition", dryRun: false },
    ]);
    assert.deepEqual(client.createdDefinitions, [{ type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." }]);
    assert.deepEqual(client.patchedDefinitions, [{ id: "definition-1", isGlobalPublished: true }]);
    assert.deepEqual(client.createdVersions.map(({ moduleDefinitionId, version, description, config }) => ({ moduleDefinitionId, version, description, config })), [
      { moduleDefinitionId: "definition-1", version: "1.2.3", description: "Add subnet options.", config: { inputs: [{ id: "name", type: "string", label: "Name" }] } },
    ]);
    assert.deepEqual(client.dryRunVersions, [
      { moduleDefinitionId: "definition-1", version: "1.2.3", description: "Add subnet options.", config: { inputs: [{ id: "name", type: "string", label: "Name" }] } },
    ]);
  });

  it("keeps a new non-global definition private after publishing its first version", async () => {
    const client = new MockRavionClient();

    const result = await publishDefinitions([createCompiledDefinition({ global: false })], client, { dryRun: false });

    assert.deepEqual(result.items.map(({ action }) => action), ["create-definition", "create-version"]);
    assert.equal(client.dryRunVersions.length, 1);
    assert.equal(client.createdVersions.length, 1);
    assert.deepEqual(client.patchedDefinitions, []);
  });

  it("does not globally publish a new definition when its first version fails validation", async () => {
    const client = new MockRavionClient();
    client.onDryRunVersion = async () => {
      throw new Error("Config is invalid");
    };

    await assert.rejects(
      () => publishDefinitions([createCompiledDefinition()], client, { dryRun: false }),
      /Config is invalid/,
    );

    assert.equal(client.createdDefinitions.length, 1);
    assert.equal(client.createdVersions.length, 0);
    assert.equal(client.patchedDefinitions.length, 0);
  });

  it("does not globally publish a new definition when its first version fails creation", async () => {
    const client = new MockRavionClient();
    client.onCreateVersion = async () => {
      throw new Error("Version creation failed");
    };

    await assert.rejects(
      () => publishDefinitions([createCompiledDefinition()], client, { dryRun: false }),
      /Version creation failed/,
    );

    assert.equal(client.dryRunVersions.length, 1);
    assert.equal(client.patchedDefinitions.length, 0);
  });

  it("preserves an existing organization-scoped definition after confirming its version", async () => {
    const compiled = createCompiledDefinition();
    const client = new MockRavionClient({
      definitions: [
        {
          id: "vpc",
          type: "ravion-aws-vpc",
          name: "AWS VPC",
          description: "AWS VPC and subnets.",
          organizationId: "organization-1",
        },
      ],
      versionsByDefinitionId: { vpc: [createRemoteVersion({ config: compiled.module })] },
    });

    const result = await publishDefinitions([compiled], client, { dryRun: false });

    assert.deepEqual(result.items.map(({ action }) => action), ["skip-version"]);
    assert.deepEqual(client.patchedDefinitions, []);
  });

  it("preserves an existing private definition in the dry-run plan", async () => {
    const compiled = createCompiledDefinition();
    const client = new MockRavionClient({
      definitions: [
        {
          id: "vpc",
          type: "ravion-aws-vpc",
          name: "AWS VPC",
          description: "AWS VPC and subnets.",
          isGlobalPublished: false,
        },
      ],
      versionsByDefinitionId: { vpc: [createRemoteVersion({ config: compiled.module })] },
    });

    const result = await publishDefinitions([compiled], client);
    const markdown = formatPublishPlanMarkdown(result);

    assert.deepEqual(result.items.map(({ action }) => action), ["skip-version"]);
    assert.doesNotMatch(markdown, /Make the module definition available globally/);
    assert.doesNotMatch(markdown, /isGlobalPublished/);
    assert.equal(client.patchedDefinitions.length, 0);
  });

  it("preserves an existing private definition when it needs a new version", async () => {
    const compiled = createCompiledDefinition();
    const client = new MockRavionClient({
      definitions: [
        {
          id: "vpc",
          type: "ravion-aws-vpc",
          name: "AWS VPC",
          description: "AWS VPC and subnets.",
          isGlobalPublished: false,
        },
      ],
      versionsByDefinitionId: {
        vpc: [createRemoteVersion({ version: "1.2.2", config: { inputs: [] } })],
      },
    });

    const result = await publishDefinitions([compiled], client, { dryRun: false });
    const markdown = formatPublishPlanMarkdown(result);

    assert.deepEqual(result.items.map(({ action }) => action), ["create-version"]);
    assert.match(markdown, /\| `ravion-aws-vpc` \| `1\.2\.2` \| `1\.2\.3` \| Add subnet options\. \|/);
    assert.doesNotMatch(markdown, /isGlobalPublished/);
    assert.equal(client.createdVersions.length, 1);
    assert.deepEqual(client.patchedDefinitions, []);
  });

  it("globally publishes an existing definition when publishing its first version", async () => {
    const client = new MockRavionClient({
      definitions: [
        {
          id: "vpc",
          type: "ravion-aws-vpc",
          name: "AWS VPC",
          description: "AWS VPC and subnets.",
          isGlobalPublished: false,
        },
      ],
    });

    const result = await publishDefinitions([createCompiledDefinition()], client, { dryRun: false });

    assert.deepEqual(result.items.map(({ action }) => action), ["create-version", "patch-definition"]);
    assert.equal(client.dryRunVersions.length, 1);
    assert.deepEqual(client.patchedDefinitions, [{ id: "vpc", isGlobalPublished: true }]);
  });

  it("retries an explicit global publication when the first visibility patch fails", async () => {
    const compiled = createCompiledDefinition({ global: true });
    const client = new MockRavionClient();
    let failGlobalPatch = true;
    client.onPatchDefinition = async (input) => {
      if (failGlobalPatch && input.isGlobalPublished) {
        failGlobalPatch = false;
        throw new Error("Global publication failed");
      }
    };

    await assert.rejects(
      () => publishDefinitions([compiled], client, { dryRun: false }),
      /Global publication failed/,
    );

    const result = await publishDefinitions([compiled], client, { dryRun: false });

    assert.deepEqual(result.items.map(({ action }) => action), ["skip-version", "patch-definition"]);
    assert.deepEqual(client.patchedDefinitions, [
      { id: "definition-1", isGlobalPublished: true },
      { id: "definition-1", isGlobalPublished: true },
    ]);
  });

  it("validates pending module versions through the server dry-run API", async () => {
    const client = new MockRavionClient({
      definitions: [{ id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." }],
    });

    const results = await dryRunModuleVersions([createCompiledDefinition()], client);

    assert.deepEqual(results, [{
      type: "ravion-aws-vpc",
      version: "1.2.3",
      status: "validated",
      message: "Module version config passed server-side dry-run validation.",
    }]);
    assert.deepEqual(client.dryRunVersions, [{
      moduleDefinitionId: "vpc",
      version: "1.2.3",
      description: "Add subnet options.",
      config: { inputs: [{ id: "name", type: "string", label: "Name" }] },
    }]);
  });

  it("aggregates server dry-run validation failures", async () => {
    const definitions = [
      createCompiledDefinition({ type: "ravion-aws-vpc" }),
      createCompiledDefinition({ type: "ravion-aws-ecs" }),
    ];
    const client = new MockRavionClient({
      definitions: [
        { id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." },
        { id: "ecs", type: "ravion-aws-ecs", name: "AWS ECS", description: "AWS ECS." },
      ],
    });
    client.onDryRunVersion = async (input) => {
      throw new Error(`Invalid config for ${input.moduleDefinitionId}`);
    };

    const results = await dryRunModuleVersions(definitions, client);

    assert.deepEqual(results.map(({ type, status, message }) => ({ type, status, message })), [
      { type: "ravion-aws-ecs", status: "failed", message: "Error: Invalid config for ecs" },
      { type: "ravion-aws-vpc", status: "failed", message: "Error: Invalid config for vpc" },
    ]);
    assert.equal(client.dryRunVersions.length, 2);
  });

  it("skips already-published and brand-new module definitions", async () => {
    const compiled = [
      createCompiledDefinition(),
      createCompiledDefinition({ type: "ravion-aws-new" }),
    ];
    const client = new MockRavionClient({
      definitions: [{ id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." }],
      versionsByDefinitionId: { vpc: [createRemoteVersion()] },
    });

    const results = await dryRunModuleVersions(compiled, client);

    assert.deepEqual(results.map(({ type, status, message }) => ({ type, status, message })), [
      {
        type: "ravion-aws-new",
        status: "skipped",
        message: "Remote module definition does not exist yet; no module definition ID is available for dry-run validation.",
      },
      {
        type: "ravion-aws-vpc",
        status: "skipped",
        message: "Release version is already published remotely.",
      },
    ]);
    assert.equal(client.dryRunVersions.length, 0);
  });

  it("patches metadata changes before publishing versions", async () => {
    const client = new MockRavionClient({ definitions: [{ id: "vpc", type: "ravion-aws-vpc", name: "Old name", description: "Old description" }] });

    const result = await publishDefinitions([createCompiledDefinition()], client, { dryRun: false });

    assert.deepEqual(result.items.map(({ action }) => action), ["patch-definition", "create-version", "patch-definition"]);
    assert.deepEqual(client.patchedDefinitions, [
      { id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." },
      { id: "vpc", isGlobalPublished: true },
    ]);
  });

  it("creates and globally publishes missing categories before module definitions", async () => {
    const definition = createCompiledDefinition({
      filePath: join("/repo", "networking", "vpc", "rvn-aws-network-definition.yml"),
      type: "rvn-aws-network",
      name: "VPC Network",
    });
    const client = new MockRavionClient();

    const result = await publishDefinitions([definition], client, { dryRun: false });

    assert.deepEqual(result.categoryItems?.map(({ givenId, action }) => ({ givenId, action })), [
      { givenId: "network", action: "create-category" },
    ]);
    assert.deepEqual(client.createdCategories, [
      {
        givenId: "network",
        name: "Network",
        description: "For private subnets, internet access, service connectivity, and shared load balancers.",
        sortOrder: 100,
      },
    ]);
    assert.deepEqual(client.patchedCategories, [
      { id: "category-1", isGlobalPublished: true },
    ]);
    assert.deepEqual(client.createdDefinitions[0].moduleCategoryIds, ["category-1"]);
  });

  it("plans missing categories without creating them during a dry run", async () => {
    const definition = createCompiledDefinition({
      filePath: join("/repo", "compute", "lambda", "rvn-lambda-definition.yml"),
      type: "rvn-lambda",
      name: "Lambda Function",
    });
    const client = new MockRavionClient();

    const result = await publishDefinitions([definition], client);

    assert.deepEqual(result.categoryItems?.map(({ givenId, action }) => ({ givenId, action })), [
      { givenId: "function", action: "create-category" },
    ]);
    assert.equal(client.createdCategories.length, 0);
    assert.equal(client.createdDefinitions.length, 0);
  });

  it("assigns existing categories to existing module definitions", async () => {
    const definition = createCompiledDefinition({
      filePath: join("/repo", "networking", "vpc", "rvn-aws-network-definition.yml"),
      type: "rvn-aws-network",
      name: "VPC Network",
    });
    const client = new MockRavionClient({
      categories: [
        {
          id: "network-category",
          givenId: "network",
          name: "Network",
          description: "For private subnets, internet access, service connectivity, and shared load balancers.",
          sortOrder: 100,
        },
      ],
      definitions: [
        {
          id: "network-definition",
          type: "rvn-aws-network",
          name: "VPC Network",
          description: definition.description,
        },
      ],
      versionsByDefinitionId: {
        "network-definition": [createRemoteVersion({ moduleDefinitionId: "network-definition", config: definition.module })],
      },
    });

    const result = await publishDefinitions([definition], client, { dryRun: false });

    assert.deepEqual(result.categoryItems, []);
    assert.deepEqual(result.items.map(({ action }) => action), ["patch-definition", "skip-version"]);
    assert.deepEqual(client.patchedDefinitions[0].moduleCategoryIds, ["network-category"]);
    assert.equal(client.createdCategories.length, 0);
  });

  it("assigns every matching category to a multi-category definition", async () => {
    const categoryGivenIds = ["web-server", "tcp-udp-server", "worker"];
    const categories = MODULE_CATEGORIES
      .filter((category) => categoryGivenIds.includes(category.givenId))
      .map((category) => ({
        id: `${category.givenId}-category`,
        givenId: category.givenId,
        name: category.name,
        description: category.description,
        sortOrder: category.sortOrder,
      }));
    const definition = createCompiledDefinition({
      filePath: join("/repo", "compute", "ec2_service", "rvn-ec2-service-definition.yml"),
      type: "rvn-ec2-service",
      name: "EC2 Service",
    });
    const client = new MockRavionClient({ categories });

    await publishDefinitions([definition], client, { dryRun: false });

    assert.deepEqual(client.createdDefinitions[0].moduleCategoryIds, [
      "web-server-category",
      "worker-category",
    ]);
  });

  it("renames a previous category ID without creating a duplicate", async () => {
    const definition = createCompiledDefinition({
      filePath: join("/repo", "compute", "ecs_service", "rvn-ecs-nlb-definition.yml"),
      type: "rvn-ecs-nlb",
      name: "ECS Network Service",
    });
    const client = new MockRavionClient({
      categories: [
        {
          id: "web-category",
          givenId: "web-server",
          name: "Web server",
          description: "For websites, HTTP APIs, and services reached through a browser or web client.",
          sortOrder: 10,
        },
        {
          id: "tcp-category",
          givenId: "tcp-udp-service",
          name: "TCP/UDP service",
          description: "Services exposed over TCP, UDP, or TLS, including HTTP without application-layer routing.",
          sortOrder: 50,
        },
      ],
      definitions: [
        {
          id: "nlb-definition",
          type: definition.type,
          name: definition.name,
          description: definition.description,
          moduleCategoryIds: ["web-category", "tcp-category"],
        },
      ],
      versionsByDefinitionId: {
        "nlb-definition": [createRemoteVersion({ moduleDefinitionId: "nlb-definition", config: definition.module })],
      },
    });

    const result = await publishDefinitions([definition], client, { dryRun: false });

    assert.deepEqual(result.categoryItems?.map(({ givenId, action }) => ({ givenId, action })), [
      { givenId: "tcp-udp-server", action: "patch-category" },
    ]);
    assert.equal(client.createdCategories.length, 0);
    assert.equal(client.patchedCategories[0].givenId, "tcp-udp-server");
    assert.equal(client.categories.find((category) => category.id === "tcp-category")?.givenId, "tcp-udp-server");
  });

  it("skips identical existing versions idempotently", async () => {
    const client = new MockRavionClient({
      definitions: [{ id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." }],
      versionsByDefinitionId: { vpc: [createRemoteVersion({ config: createCompiledDefinition().module })] },
    });

    const result = await publishDefinitions([createCompiledDefinition()], client, { dryRun: false });

    assert.deepEqual(result.items.map(({ action }) => action), ["skip-version"]);
    assert.equal(client.createdVersions.length, 0);
  });

  it("fails with structured conflict details when an existing version has different config", async () => {
    const remoteConfig = {
      inputs: [
        { id: "unchanged-first", type: "string", label: "Unchanged First" },
        { id: "unchanged-second", type: "string", label: "Unchanged Second" },
        { id: "unchanged-third", type: "string", label: "Unchanged Third" },
        { id: "unchanged-fourth", type: "string", label: "Unchanged Fourth" },
        { id: "latest", type: "string", label: "Latest" },
        { id: "unchanged-fifth", type: "string", label: "Unchanged Fifth" },
      ],
    };
    const localConfig = {
      inputs: [
        { id: "unchanged-first", type: "string", label: "Unchanged First" },
        { id: "unchanged-second", type: "string", label: "Unchanged Second" },
        { id: "unchanged-third", type: "string", label: "Unchanged Third" },
        { id: "unchanged-fourth", type: "string", label: "Unchanged Fourth" },
        { id: "name", type: "string", label: "Name" },
        { id: "unchanged-fifth", type: "string", label: "Unchanged Fifth" },
      ],
    };
    const client = new MockRavionClient({
      definitions: [{ id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." }],
      versionsByDefinitionId: {
        vpc: [
          createRemoteVersion({ version: "1.2.3", config: { inputs: [{ id: "region", type: "string", label: "Region" }] } }),
          createRemoteVersion({ version: "1.2.4", config: remoteConfig }),
        ],
      },
    });

    await assert.rejects(
      () => publishDefinitions([createCompiledDefinition({ module: localConfig })], client),
      (error) => {
        assert.ok(error instanceof PublishPlanError);
        assert.deepEqual(error.result.errors?.map(({ type, version, latestVersion, message }) => ({ type, version, latestVersion, message })), [
          {
            type: "ravion-aws-vpc",
            version: "1.2.3",
            latestVersion: "1.2.4",
            message: "Release version already exists remotely with different compiled config.",
          },
        ]);
        assert.match(formatPublishPlanMarkdown(error.result), /### 🚨 Release Config Conflicts 🚨/);
        assert.match(formatPublishPlanMarkdown(error.result), /Latest Remote vs Compiled/);
        assert.match(formatPublishPlanMarkdown(error.result), /#### ravion-aws-vpc 1\.2\.4 -> 1\.2\.3/);
        assert.doesNotMatch(formatPublishPlanMarkdown(error.result), /<details>/);
        assert.match(formatPublishPlanMarkdown(error.result), /```diff/);
        assert.match(formatPublishPlanMarkdown(error.result), /-  - id: latest/);
        assert.match(formatPublishPlanMarkdown(error.result), /\+  - id: name/);
        assert.doesNotMatch(formatPublishPlanMarkdown(error.result), /unchanged-first/);
        return true;
      },
    );
  });

  it("sends release.description as ModuleVersion.description", async () => {
    const client = new MockRavionClient({ definitions: [{ id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." }] });

    await publishDefinitions([createCompiledDefinition({ releaseDescription: "Curated changelog entry." })], client, { dryRun: false });

    assert.equal(client.createdVersions[0].description, "Curated changelog entry.");
  });

  it("does not mutate the API in dry-run mode", async () => {
    const client = new MockRavionClient();

    const result = await publishDefinitions([createCompiledDefinition()], client);

    assert.equal(result.dryRun, true);
    assert.deepEqual(result.items.map(({ action }) => action), ["create-definition", "create-version", "patch-definition"]);
    assert.equal(client.createdDefinitions.length, 0);
    assert.equal(client.createdVersions.length, 0);
  });

  it("local-dev publishing starts at the first suffixed version when no versions exist remotely", async () => {
    const client = new MockRavionClient({ definitions: [{ id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." }] });

    await publishDefinitions([createCompiledDefinition()], client, { dryRun: false, localDev: true });

    assert.equal(client.createdVersions[0].version, "1.2.3-1");
  });

  it("local-dev publishing uses the first suffix when the base version has different config", async () => {
    const client = new MockRavionClient({
      definitions: [{ id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." }],
      versionsByDefinitionId: { vpc: [createRemoteVersion({ config: { inputs: [{ id: "region", type: "string", label: "Region" }] } })] },
    });

    const result = await publishDefinitions([createCompiledDefinition()], client, { dryRun: false, localDev: true });

    assert.deepEqual(result.items.map(({ action, version }) => ({ action, version })), [{ action: "create-version", version: "1.2.3-1" }]);
    assert.equal(client.createdVersions[0].version, "1.2.3-1");
  });

  it("local-dev publishing chooses the next suffix and uses the source ref in compiled config", async () => {
    const compiled = createCompiledDefinition({
      module: {
        stack: {
          source: { branch: "main", ref: "ravion-aws-vpc@1.2.3" },
        },
        readme: "Terraform source ravion-aws-vpc@1.2.3",
      },
    });
    const client = new MockRavionClient({
      definitions: [{ id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." }],
      versionsByDefinitionId: {
        vpc: [
          createRemoteVersion({ config: { changed: true } }),
          createRemoteVersion({ version: "1.2.3-1", config: { changed: true } }),
          createRemoteVersion({ version: "1.2.3-2", config: { changed: true } }),
        ],
      },
    });

    await publishDefinitions([compiled], client, { dryRun: false, localDev: true });

    assert.equal(client.createdVersions[0].version, "1.2.3-3");
    assert.deepEqual(client.createdVersions[0].config, {
      stack: { source: { branch: "main", ref: "main" } },
      readme: "Terraform source main",
    });
  });

  it("local-dev publishing uses the provided source ref in compiled config", async () => {
    const compiled = createCompiledDefinition({ module: { stack: { source: { branch: "main", ref: "ravion-aws-vpc@1.2.3" } } } });
    const client = new MockRavionClient({ definitions: [{ id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." }] });

    await publishDefinitions([compiled], client, { dryRun: false, localDev: true, localDevSourceRef: "feature-branch" });

    assert.equal(client.createdVersions[0].version, "1.2.3-1");
    assert.deepEqual(client.createdVersions[0].config, { stack: { source: { branch: "feature-branch", ref: "feature-branch" } } });
  });

  it("local-dev publishing skips an identical existing suffixed version", async () => {
    const compiled = createCompiledDefinition({ module: { stack: { source: { ref: "ravion-aws-vpc@1.2.3" } } } });
    const suffixedConfig = { stack: { source: { ref: "main" } } };
    const client = new MockRavionClient({
      definitions: [{ id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." }],
      versionsByDefinitionId: {
        vpc: [createRemoteVersion({ config: { changed: true } }), createRemoteVersion({ version: "1.2.3-1", config: suffixedConfig })],
      },
    });

    const result = await publishDefinitions([compiled], client, { dryRun: false, localDev: true });

    assert.deepEqual(result.items.map(({ action, version }) => ({ action, version })), [{ action: "skip-version", version: "1.2.3-1" }]);
    assert.equal(client.createdVersions.length, 0);
  });

  it("local-dev force publishing chooses the next suffix when an identical suffixed version exists", async () => {
    const compiled = createCompiledDefinition({ module: { stack: { source: { ref: "ravion-aws-vpc@1.2.3" } } } });
    const suffixedConfig = { stack: { source: { ref: "main" } } };
    const client = new MockRavionClient({
      definitions: [{ id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." }],
      versionsByDefinitionId: {
        vpc: [createRemoteVersion({ version: "1.2.3-1", config: suffixedConfig })],
      },
    });

    const result = await publishDefinitions([compiled], client, { dryRun: false, localDev: true, localDevForce: true });

    assert.deepEqual(result.items.map(({ action, version }) => ({ action, version })), [{ action: "create-version", version: "1.2.3-2" }]);
    assert.equal(client.createdVersions[0].version, "1.2.3-2");
  });

  it("formats a markdown dry-run plan with diffs", async () => {
    const client = new MockRavionClient();

    const result = await publishDefinitions([createCompiledDefinition()], client);
    const markdown = formatPublishPlanMarkdown(result);

    assert.match(markdown, /<!-- ravion-module-publish-plan -->/);
    assert.match(markdown, /Dry run only/);
    assert.match(markdown, /\| Module \| Current Version \| New Version \| Description \|/);
    assert.match(markdown, /\| `ravion-aws-vpc` \| n\/a \| `1\.2\.3` \| Add subnet options\. \|/);
    assert.doesNotMatch(markdown, /\| `ravion-aws-vpc` \| n\/a \| `1\.2\.3` \| AWS VPC and subnets\. \|/);
    assert.match(markdown, /#### ravion-aws-vpc n\/a -> 1\.2\.3/);
    assert.doesNotMatch(markdown, /<details>/);
    assert.match(markdown, /```diff/);
    assert.match(markdown, /\+type: ravion-aws-vpc/);
  });

  it("omits unchanged modules from the markdown plan", async () => {
    const client = new MockRavionClient({
      definitions: [{ id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." }],
      versionsByDefinitionId: { vpc: [createRemoteVersion({ config: createCompiledDefinition().module })] },
    });

    const result = await publishDefinitions([createCompiledDefinition()], client);
    const markdown = formatPublishPlanMarkdown(result);

    assert.match(markdown, /No publish changes are required/);
    assert.doesNotMatch(markdown, /\| Module \| Current Version \| New Version \| Description \|/);
    assert.doesNotMatch(markdown, /\| Module \| Version \| Action \| Summary \|/);
    assert.doesNotMatch(markdown, /Skip ravion-aws-vpc@1\.2\.3/);
  });

  it("lists planned changes sorted by module and omits skipped modules from the markdown table", () => {
    const item = (type: string, action: "create-version" | "skip-version") => ({ type, version: "1.0.0", action, dryRun: true, message: `${action} ${type}`, description: `${action} ${type}` });
    const markdown = formatPublishPlanMarkdown({
      dryRun: true,
      items: [item("aaa-skipped", "skip-version"), item("zzz-changed", "create-version"), item("bbb-changed", "create-version"), item("yyy-skipped", "skip-version")],
    });

    const rows = markdown.split("\n").filter((line) => line.startsWith("| `"));
    assert.deepEqual(
      rows.map((row) => row.split("|")[1].trim()),
      ["`bbb-changed`", "`zzz-changed`"],
    );
    assert.doesNotMatch(markdown, /aaa-skipped/);
    assert.doesNotMatch(markdown, /yyy-skipped/);
  });

  it("requires a Ravion API token by default", async () => {
    await assert.rejects(() => createDefaultRavionApiClient({ token: "" }), {
      name: "PublishError",
      message: "RAVION_API_TOKEN must be set to read or publish module definitions through the Ravion API.",
    });
  });

  it("uses RAVION_API_URL as the default API base URL", async () => {
    const originalFetch = globalThis.fetch;
    const originalApiUrl = process.env.RAVION_API_URL;
    const calls: string[] = [];
    process.env.RAVION_API_URL = "http://localhost:8080";
    globalThis.fetch = async (url) => {
      calls.push(String(url));
      return jsonResponse({ data: [], meta: { limit: 100 } });
    };

    try {
      const client = await createDefaultRavionApiClient({ token: "token" });
      await client.listModuleDefinitions();
    } finally {
      globalThis.fetch = originalFetch;
      if (originalApiUrl === undefined) {
        delete process.env.RAVION_API_URL;
      } else {
        process.env.RAVION_API_URL = originalApiUrl;
      }
    }

    assert.deepEqual(calls, ["http://localhost:8080/module-definitions?limit=100"]);
  });

  it("can create a client without a token when token requirement is disabled", async () => {
    const client = await createDefaultRavionApiClient({ baseUrl: "http://localhost:8080", token: "", requireToken: false });

    assert.ok(client);
  });

  it("adds inventory context when loading remote versions fails", async () => {
    const logs: string[] = [];
    const client = new MockRavionClient({ definitions: [{ id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." }] });
    client.onListModuleVersions = async () => {
      throw new Error("Forbidden");
    };

    await assert.rejects(() => publishDefinitions([createCompiledDefinition()], client, { logger: (message) => logs.push(message) }), {
      name: "PublishError",
      message: "Failed to list remote module versions for ravion-aws-vpc (vpc): Error: Forbidden",
    });
    assert.deepEqual(logs, ["Loading remote module definitions from Ravion API.", "Loading remote module versions for 1 definitions."]);
  });

  it("uses the OpenAPI REST endpoints and data envelopes", async () => {
    const calls: Array<{ url: string; method: string; body?: unknown }> = [];
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async (url, init) => {
      calls.push({ url: String(url), method: init?.method ?? "GET", body: init?.body ? JSON.parse(String(init.body)) : undefined });
      if (String(url).includes("/module-categories?")) {
        return jsonResponse({ data: [{ id: "network", givenId: "network", name: "Network", sortOrder: 10 }], meta: { limit: 100 } });
      }
      if (String(url).includes("/module-definitions?")) {
        return jsonResponse({ data: [{ id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." }], meta: { limit: 100 } });
      }
      if (String(url).includes("/module-versions?")) {
        return jsonResponse({ data: [], meta: { limit: 100 } });
      }
      if (String(url).endsWith("/module-categories")) {
        return jsonResponse({ data: { id: "created-category", givenId: "worker", name: "Worker", sortOrder: 20 } }, 201);
      }
      if (String(url).endsWith("/module-categories/network")) {
        return jsonResponse({ data: { id: "network", givenId: "network", name: "Network", sortOrder: 10 } });
      }
      if (String(url).endsWith("/module-definitions")) {
        return jsonResponse({ data: { id: "created", type: "ravion-aws-new", name: "New", description: "New module." } }, 201);
      }
      if (String(url).endsWith("/module-definitions/vpc")) {
        return jsonResponse({ data: { id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "New description." } });
      }
      if (String(url).endsWith("/module-versions")) {
        const body = init?.body ? JSON.parse(String(init.body)) : undefined;
        if (body?.data?.dryRun === true) {
          return jsonResponse({ data: { moduleDefinitionId: "vpc", version: "1.2.3", config: { inputs: [] } } }, 202);
        }
        return jsonResponse({ data: { id: "version", moduleDefinitionId: "vpc", version: "1.2.3", description: "Add subnet options.", config: {} } }, 201);
      }
      throw new Error(`Unexpected fetch URL ${url}`);
    };

    try {
      const client = await createDefaultRavionApiClient({ baseUrl: "https://api.example.test", token: "token" });
      await client.listModuleCategories();
      await client.createModuleCategory({ givenId: "worker", name: "Worker", sortOrder: 20 });
      await client.patchModuleCategory({ id: "network", name: "Network", isGlobalPublished: true });
      await client.listModuleDefinitions();
      await client.listModuleVersions("vpc");
      await client.createModuleDefinition({ type: "ravion-aws-new", name: "New", description: "New module.", moduleCategoryIds: ["network"] });
      await client.patchModuleDefinition({ id: "vpc", name: "AWS VPC", description: "New description.", moduleCategoryIds: ["network"] });
      await client.createModuleVersion({ moduleDefinitionId: "vpc", version: "1.2.3", description: "Add subnet options.", config: {} });
      await client.dryRunModuleVersion({ moduleDefinitionId: "vpc", version: "1.2.3", description: "Add subnet options.", config: {} });
    } finally {
      globalThis.fetch = originalFetch;
    }

    assert.deepEqual(calls, [
      { url: "https://api.example.test/module-categories?limit=100", method: "GET", body: undefined },
      { url: "https://api.example.test/module-categories", method: "POST", body: { data: { givenId: "worker", name: "Worker", sortOrder: 20 } } },
      { url: "https://api.example.test/module-categories/network", method: "PATCH", body: { data: { name: "Network", isGlobalPublished: true } } },
      { url: "https://api.example.test/module-definitions?limit=100", method: "GET", body: undefined },
      { url: "https://api.example.test/module-versions?moduleDefinitionId=vpc&limit=100", method: "GET", body: undefined },
      { url: "https://api.example.test/module-definitions", method: "POST", body: { data: { type: "ravion-aws-new", name: "New", description: "New module.", moduleCategoryIds: ["network"] } } },
      { url: "https://api.example.test/module-definitions/vpc", method: "PATCH", body: { data: { name: "AWS VPC", description: "New description.", moduleCategoryIds: ["network"] } } },
      {
        url: "https://api.example.test/module-versions",
        method: "POST",
        body: { data: { moduleDefinitionId: "vpc", version: "1.2.3", description: "Add subnet options.", config: {} } },
      },
      {
        url: "https://api.example.test/module-versions",
        method: "POST",
        body: { data: { moduleDefinitionId: "vpc", version: "1.2.3", description: "Add subnet options.", config: {}, dryRun: true } },
      },
    ]);
  });

  it("includes REST error response details", async () => {
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async () => jsonResponse({ code: "Ravion:Auth:FORBIDDEN", message: "Forbidden", description: "Missing scope", requestId: "req_123" }, 403);

    try {
      const client = await createDefaultRavionApiClient({ baseUrl: "https://api.example.test", token: "token" });
      await assert.rejects(() => client.listModuleDefinitions(), {
        name: "HttpApiError",
        message:
          'GET https://api.example.test/module-definitions?limit=100 failed with HTTP 403: code=Ravion:Auth:FORBIDDEN; Forbidden; Missing scope; requestId=req_123\nResponse body:\n{\n  "code": "Ravion:Auth:FORBIDDEN",\n  "message": "Forbidden",\n  "description": "Missing scope",\n  "requestId": "req_123"\n}',
      });
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("handles duplicate version responses as an idempotent skip when the remote config matches", async () => {
    const compiled = createCompiledDefinition();
    const client = new MockRavionClient({ definitions: [{ id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." }] });
    client.onCreateVersion = async (input) => {
      client.versionsByDefinitionId[input.moduleDefinitionId] = [createRemoteVersion({ config: compiled.module })];
      throw new Error("Duplicate version already exists");
    };

    const result = await publishDefinitions([compiled], client, { dryRun: false });

    assert.deepEqual(result.items.map(({ action }) => action), ["create-version", "patch-definition"]);
  });

  it("fails duplicate version responses when the remote config differs", async () => {
    const client = new MockRavionClient({ definitions: [{ id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." }] });
    client.onCreateVersion = async (input) => {
      client.versionsByDefinitionId[input.moduleDefinitionId] = [createRemoteVersion({ config: { inputs: [{ id: "region", type: "string", label: "Region" }] } })];
      throw new Error("Duplicate version already exists");
    };

    await assert.rejects(() => publishDefinitions([createCompiledDefinition()], client, { dryRun: false }), (error) => error instanceof PublishError);
  });
});

function createCompiledDefinition(overrides: Partial<CompiledDefinition> = {}): CompiledDefinition {
  return {
    filePath: join("/repo", "networking", "vpc", "ravion-aws-vpc-definition.yml"),
    published: true,
    type: "ravion-aws-vpc",
    name: "AWS VPC",
    description: "AWS VPC and subnets.",
    version: "1.2.3",
    releaseDescription: "Add subnet options.",
    module: { inputs: [{ id: "name", type: "string", label: "Name" }] },
    ...overrides,
  };
}

function createRemoteVersion(overrides: Partial<RemoteModuleVersion> = {}): RemoteModuleVersion {
  return {
    moduleDefinitionId: "vpc",
    version: "1.2.3",
    description: "Add subnet options.",
    config: { inputs: [{ id: "name", type: "string", label: "Name" }] },
    ...overrides,
  };
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

class MockRavionClient implements RavionModuleApiClient {
  categories: RemoteModuleCategory[];
  definitions: RemoteModuleDefinition[];
  versionsByDefinitionId: Record<string, RemoteModuleVersion[]>;
  createdCategories: ModuleCategoryInput[] = [];
  patchedCategories: ModuleCategoryPatchInput[] = [];
  createdDefinitions: ModuleDefinitionInput[] = [];
  patchedDefinitions: ModuleDefinitionPatchInput[] = [];
  createdVersions: ModuleVersionInput[] = [];
  dryRunVersions: ModuleVersionInput[] = [];
  onListModuleVersions?: (moduleDefinitionId: string) => Promise<RemoteModuleVersion[]>;
  onCreateVersion?: (input: ModuleVersionInput) => Promise<void>;
  onDryRunVersion?: (input: ModuleVersionInput) => Promise<void>;
  onPatchDefinition?: (input: ModuleDefinitionPatchInput) => Promise<void>;

  constructor(options: { categories?: RemoteModuleCategory[]; definitions?: RemoteModuleDefinition[]; versionsByDefinitionId?: Record<string, RemoteModuleVersion[]> } = {}) {
    this.categories = options.categories ?? [];
    this.definitions = options.definitions ?? [];
    this.versionsByDefinitionId = options.versionsByDefinitionId ?? {};
  }

  async listModuleCategories(): Promise<RemoteModuleCategory[]> {
    return this.categories;
  }

  async createModuleCategory(input: ModuleCategoryInput): Promise<RemoteModuleCategory> {
    this.createdCategories.push(input);
    const category = {
      id: `category-${this.categories.length + 1}`,
      organizationId: "organization-1",
      ...input,
    };
    this.categories.push(category);
    return category;
  }

  async patchModuleCategory(input: ModuleCategoryPatchInput): Promise<RemoteModuleCategory> {
    this.patchedCategories.push(input);
    const { id, isGlobalPublished } = input;
    const updates = {
      ...(input.givenId !== undefined ? { givenId: input.givenId } : {}),
      ...(input.name !== undefined ? { name: input.name } : {}),
      ...(input.description !== undefined ? { description: input.description ?? undefined } : {}),
      ...(input.icon !== undefined ? { icon: input.icon ?? undefined } : {}),
      ...(input.sortOrder !== undefined ? { sortOrder: input.sortOrder } : {}),
    };
    this.categories = this.categories.map((category) => {
      if (category.id !== id) {
        return category;
      }
      const updated = { ...category, ...updates };
      if (isGlobalPublished === true) {
        const { organizationId: _organizationId, ...globalCategory } = updated;
        return globalCategory;
      }
      return updated;
    });
    const category = this.categories.find((item) => item.id === id);
    if (!category) {
      throw new Error(`Category ${id} not found`);
    }
    return category;
  }

  async listModuleDefinitions(): Promise<RemoteModuleDefinition[]> {
    return this.definitions;
  }

  async createModuleDefinition(input: ModuleDefinitionInput): Promise<RemoteModuleDefinition> {
    this.createdDefinitions.push(input);
    const definition = { id: `definition-${this.definitions.length + 1}`, ...input };
    this.definitions.push(definition);
    return definition;
  }

  async patchModuleDefinition(input: ModuleDefinitionPatchInput): Promise<RemoteModuleDefinition> {
    this.patchedDefinitions.push(input);
    if (this.onPatchDefinition) {
      await this.onPatchDefinition(input);
    }
    const patched = this.definitions.map((definition) => {
      if (definition.id !== input.id) {
        return definition;
      }
      const updated = { ...definition, ...input };
      if (input.isGlobalPublished === true) {
        const { organizationId: _organizationId, ...globalDefinition } = updated;
        return globalDefinition;
      }
      return updated;
    });
    this.definitions = patched;
    const definition = patched.find((item) => item.id === input.id);
    if (!definition) {
      throw new Error(`Definition ${input.id} not found`);
    }
    return definition;
  }

  async listModuleVersions(moduleDefinitionId: string): Promise<RemoteModuleVersion[]> {
    if (this.onListModuleVersions) {
      return this.onListModuleVersions(moduleDefinitionId);
    }
    return this.versionsByDefinitionId[moduleDefinitionId] ?? [];
  }

  async createModuleVersion(input: ModuleVersionInput): Promise<RemoteModuleVersion> {
    if (this.onCreateVersion) {
      await this.onCreateVersion(input);
    }
    this.createdVersions.push(input);
    const version = { ...input };
    this.versionsByDefinitionId[input.moduleDefinitionId] = [...(this.versionsByDefinitionId[input.moduleDefinitionId] ?? []), version];
    return version;
  }

  async dryRunModuleVersion(input: ModuleVersionInput) {
    this.dryRunVersions.push(input);
    if (this.onDryRunVersion) {
      await this.onDryRunVersion(input);
    }
    return {
      moduleDefinitionId: input.moduleDefinitionId,
      version: input.version,
      config: input.config,
    };
  }
}
