import assert from "node:assert/strict";
import { join } from "node:path";
import { describe, it } from "node:test";
import { type CompiledDefinition } from "../src/compiler.js";
import { type RemoteModuleDefinition, type RemoteModuleVersion } from "../src/generate-definitions.js";
import {
  createDefaultRavionApiClient,
  formatPublishPlanMarkdown,
  PublishPlanError,
  publishDefinitions,
  PublishError,
  type ModuleDefinitionInput,
  type ModuleDefinitionPatchInput,
  type ModuleVersionInput,
  type RavionModuleApiClient,
} from "../src/publish.js";

describe("publish", () => {
  it("creates missing definitions and versions through the Ravion API", async () => {
    const client = new MockRavionClient();

    const result = await publishDefinitions([createCompiledDefinition()], client, { dryRun: false });

    assert.deepEqual(result.items.map(({ action, dryRun }) => ({ action, dryRun })), [
      { action: "create-definition", dryRun: false },
      { action: "create-version", dryRun: false },
    ]);
    assert.deepEqual(client.createdDefinitions, [{ type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." }]);
    assert.deepEqual(client.patchedDefinitions, [{ id: "definition-1", isGlobalPublished: true }]);
    assert.deepEqual(client.createdVersions.map(({ moduleDefinitionId, version, description, config }) => ({ moduleDefinitionId, version, description, config })), [
      { moduleDefinitionId: "definition-1", version: "1.2.3", description: "Add subnet options.", config: { inputs: [{ id: "name", type: "string", label: "Name" }] } },
    ]);
  });

  it("patches metadata changes before publishing versions", async () => {
    const client = new MockRavionClient({ definitions: [{ id: "vpc", type: "ravion-aws-vpc", name: "Old name", description: "Old description" }] });

    const result = await publishDefinitions([createCompiledDefinition()], client, { dryRun: false });

    assert.deepEqual(result.items.map(({ action }) => action), ["patch-definition", "create-version"]);
    assert.deepEqual(client.patchedDefinitions, [{ id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." }]);
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

  it("validates create-version items remotely during dry run when requested", async () => {
    const client = new MockRavionClient({
      definitions: [{ id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." }],
    });

    const result = await publishDefinitions([createCompiledDefinition()], client, { dryRun: true, validateRemote: true });

    assert.deepEqual(result.items.map(({ action, dryRun }) => ({ action, dryRun })), [{ action: "create-version", dryRun: true }]);
    assert.deepEqual(client.validatedVersions, [
      { moduleDefinitionId: "vpc", version: "1.2.3", description: "Add subnet options.", config: { inputs: [{ id: "name", type: "string", label: "Name" }] } },
    ]);
    assert.equal(client.createdVersions.length, 0);
  });

  it("fails the dry run with validation details when the API rejects a config", async () => {
    const client = new MockRavionClient({
      definitions: [{ id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." }],
    });
    client.onValidateVersion = async () => {
      throw new Error('POST /module-versions failed with HTTP 422: inputs.0.required: field is not allowed');
    };

    await assert.rejects(
      publishDefinitions([createCompiledDefinition()], client, { dryRun: true, validateRemote: true }),
      (error: unknown) => {
        assert.ok(error instanceof PublishPlanError);
        assert.deepEqual(error.result.validationErrors, [
          { type: "ravion-aws-vpc", version: "1.2.3", message: "Error: POST /module-versions failed with HTTP 422: inputs.0.required: field is not allowed" },
        ]);
        const markdown = formatPublishPlanMarkdown(error.result);
        assert.match(markdown, /Remote Validation Failures/);
        assert.match(markdown, /field is not allowed/);
        return true;
      },
    );
    assert.equal(client.createdVersions.length, 0);
  });

  it("skips remote validation for definitions that do not exist remotely yet", async () => {
    const client = new MockRavionClient();

    const result = await publishDefinitions([createCompiledDefinition()], client, { dryRun: true, validateRemote: true });

    assert.deepEqual(result.items.map(({ action }) => action), ["create-definition", "create-version"]);
    assert.equal(client.validatedVersions.length, 0);
    assert.equal(client.createdVersions.length, 0);
  });

  it("does not validate remotely during dry run when not requested", async () => {
    const client = new MockRavionClient({
      definitions: [{ id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." }],
    });

    await publishDefinitions([createCompiledDefinition()], client, { dryRun: true });

    assert.equal(client.validatedVersions.length, 0);
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
    assert.deepEqual(result.items.map(({ action }) => action), ["create-definition", "create-version"]);
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
      if (String(url).includes("/module-definitions?")) {
        return jsonResponse({ data: [{ id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "AWS VPC and subnets." }], meta: { limit: 100 } });
      }
      if (String(url).includes("/module-versions?")) {
        return jsonResponse({ data: [], meta: { limit: 100 } });
      }
      if (String(url).endsWith("/module-definitions")) {
        return jsonResponse({ data: { id: "created", type: "ravion-aws-new", name: "New", description: "New module." } }, 201);
      }
      if (String(url).endsWith("/module-definitions/vpc")) {
        return jsonResponse({ data: { id: "vpc", type: "ravion-aws-vpc", name: "AWS VPC", description: "New description." } });
      }
      if (String(url).endsWith("/module-versions")) {
        return jsonResponse({ data: { id: "version", moduleDefinitionId: "vpc", version: "1.2.3", description: "Add subnet options.", config: {} } }, 201);
      }
      throw new Error(`Unexpected fetch URL ${url}`);
    };

    try {
      const client = await createDefaultRavionApiClient({ baseUrl: "https://api.example.test", token: "token" });
      await client.listModuleDefinitions();
      await client.listModuleVersions("vpc");
      await client.createModuleDefinition({ type: "ravion-aws-new", name: "New", description: "New module." });
      await client.patchModuleDefinition({ id: "vpc", name: "AWS VPC", description: "New description." });
      await client.createModuleVersion({ moduleDefinitionId: "vpc", version: "1.2.3", description: "Add subnet options.", config: {} });
    } finally {
      globalThis.fetch = originalFetch;
    }

    assert.deepEqual(calls, [
      { url: "https://api.example.test/module-definitions?limit=100", method: "GET", body: undefined },
      { url: "https://api.example.test/module-versions?moduleDefinitionId=vpc&limit=100", method: "GET", body: undefined },
      { url: "https://api.example.test/module-definitions", method: "POST", body: { data: { type: "ravion-aws-new", name: "New", description: "New module." } } },
      { url: "https://api.example.test/module-definitions/vpc", method: "PATCH", body: { data: { name: "AWS VPC", description: "New description." } } },
      {
        url: "https://api.example.test/module-versions",
        method: "POST",
        body: { data: { moduleDefinitionId: "vpc", version: "1.2.3", description: "Add subnet options.", config: {} } },
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

    assert.deepEqual(result.items.map(({ action }) => action), ["create-version"]);
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
  definitions: RemoteModuleDefinition[];
  versionsByDefinitionId: Record<string, RemoteModuleVersion[]>;
  createdDefinitions: ModuleDefinitionInput[] = [];
  patchedDefinitions: ModuleDefinitionPatchInput[] = [];
  createdVersions: ModuleVersionInput[] = [];
  validatedVersions: ModuleVersionInput[] = [];
  onListModuleVersions?: (moduleDefinitionId: string) => Promise<RemoteModuleVersion[]>;
  onCreateVersion?: (input: ModuleVersionInput) => Promise<void>;
  onValidateVersion?: (input: ModuleVersionInput) => Promise<void>;

  constructor(options: { definitions?: RemoteModuleDefinition[]; versionsByDefinitionId?: Record<string, RemoteModuleVersion[]> } = {}) {
    this.definitions = options.definitions ?? [];
    this.versionsByDefinitionId = options.versionsByDefinitionId ?? {};
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
    const patched = this.definitions.map((definition) => (definition.id === input.id ? { ...definition, ...input } : definition));
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

  async validateModuleVersion(input: ModuleVersionInput): Promise<void> {
    if (this.onValidateVersion) {
      await this.onValidateVersion(input);
    }
    this.validatedVersions.push(input);
  }
}
