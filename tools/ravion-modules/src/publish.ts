import { type CompiledDefinition } from "./compiler.js";
import {
  type RemoteModuleDefinition,
  type RemoteModuleInventory,
  type RemoteModuleVersion,
} from "./generate-definitions.js";
import {
  getModuleCategoriesForDefinitionType,
  type ModuleCategorySpec,
} from "./module-categories.js";
import { getReleaseStatuses, type ReleaseStatus, validateReleaseStatuses } from "./release.js";
import YAML from "yaml";

export type PublishAction =
  | "create-definition"
  | "patch-definition"
  | "create-version"
  | "skip-version";

export interface PublishPlanItem {
  type: string;
  version: string;
  currentVersion?: string;
  action: PublishAction;
  dryRun: boolean;
  message: string;
  description: string;
  diff?: string;
}

export interface PublishResult {
  dryRun: boolean;
  categoryItems?: ModuleCategoryPublishPlanItem[];
  items: PublishPlanItem[];
  errors?: PublishPlanErrorItem[];
}

export interface ModuleCategoryPublishPlanItem {
  givenId: string;
  action: "create-category" | "patch-category";
  dryRun: boolean;
  message: string;
  diff?: string;
}

export interface PublishPlanErrorItem {
  type: string;
  version: string;
  message: string;
  latestVersion?: string;
  diff?: string;
}

export interface ModuleDefinitionInput {
  type: string;
  name: string;
  description: string;
  moduleCategoryIds?: string[];
}

export interface ModuleDefinitionPatchInput {
  id: string;
  name?: string;
  description?: string;
  moduleCategoryIds?: string[];
  isGlobalPublished?: boolean;
}

export interface RemoteModuleCategory {
  id: string;
  organizationId?: string;
  givenId: string;
  name: string;
  description?: string;
  icon?: string;
  sortOrder: number;
}

export interface ModuleCategoryInput {
  givenId: string;
  name: string;
  description?: string;
  icon?: string;
  sortOrder: number;
}

export interface ModuleCategoryPatchInput {
  id: string;
  givenId?: string;
  name?: string;
  description?: string | null;
  icon?: string | null;
  sortOrder?: number;
  isGlobalPublished?: boolean;
}

export interface ModuleVersionInput {
  moduleDefinitionId: string;
  version: string;
  description: string;
  config: Record<string, unknown>;
}

export interface ModuleVersionDryRunResponse {
  moduleDefinitionId: string;
  version: string;
  config: Record<string, unknown>;
}

export type ModuleVersionDryRunStatus = "validated" | "skipped" | "failed";

export interface ModuleVersionDryRunResult {
  type: string;
  version: string;
  status: ModuleVersionDryRunStatus;
  message: string;
}

export interface RavionApiClientOptions {
  baseUrl?: string;
  token?: string;
  requireToken?: boolean;
}

export interface PublishOptions {
  dryRun?: boolean;
  localDev?: boolean;
  localDevForce?: boolean;
  localDevSourceRef?: string;
  logger?: (message: string) => void;
}

export interface ModuleVersionDryRunOptions {
  localDev?: boolean;
  localDevForce?: boolean;
  localDevSourceRef?: string;
  logger?: (message: string) => void;
}

const DEFAULT_RAVION_API_URL = "https://api.ravion.com";

export interface RavionModuleApiClient {
  listModuleCategories(): Promise<RemoteModuleCategory[]>;
  createModuleCategory(input: ModuleCategoryInput): Promise<RemoteModuleCategory>;
  patchModuleCategory(input: ModuleCategoryPatchInput): Promise<RemoteModuleCategory>;
  listModuleDefinitions(): Promise<RemoteModuleDefinition[]>;
  createModuleDefinition(input: ModuleDefinitionInput): Promise<RemoteModuleDefinition>;
  patchModuleDefinition(input: ModuleDefinitionPatchInput): Promise<RemoteModuleDefinition>;
  listModuleVersions(moduleDefinitionId: string): Promise<RemoteModuleVersion[]>;
  createModuleVersion(input: ModuleVersionInput): Promise<RemoteModuleVersion>;
  dryRunModuleVersion(input: ModuleVersionInput): Promise<ModuleVersionDryRunResponse>;
}

export class PublishError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PublishError";
  }
}

export class PublishPlanError extends Error {
  constructor(
    message: string,
    readonly result: PublishResult,
  ) {
    super(message);
    this.name = "PublishPlanError";
  }
}

export async function publishDefinitions(
  compiledDefinitions: CompiledDefinition[],
  client: RavionModuleApiClient,
  options: PublishOptions = {},
): Promise<PublishResult> {
  const dryRun = options.dryRun ?? true;
  const publishedDefinitions = compiledDefinitions.filter((definition) => definition.published);
  if (publishedDefinitions.length === 0) {
    return { dryRun, categoryItems: [], items: [] };
  }
  const inventory = await loadRemoteInventory(client, { logger: options.logger });
  options.logger?.(`Loaded ${inventory.definitions.length} remote module definitions.`);
  const definitionsToPublish = options.localDev
    ? applyLocalDevVersions(publishedDefinitions, inventory, options.localDevSourceRef ?? "main", {
        force: options.localDevForce,
      })
    : publishedDefinitions;
  const statuses = getReleaseStatuses(definitionsToPublish, { inventory });
  const errors = createPublishPlanErrors(statuses, definitionsToPublish, inventory);
  if (errors.length > 0) {
    throw new PublishPlanError("Release metadata validation failed.", {
      dryRun,
      items: [],
      errors,
    });
  }
  validateReleaseStatuses(statuses);

  const categoryResult = await publishModuleCategories(definitionsToPublish, client, dryRun, options.logger);

  const definitionsByType = new Map(
    inventory.definitions.map((definition) => [definition.type, definition]),
  );
  const items: PublishPlanItem[] = [];

  for (const definition of [...definitionsToPublish].sort((left, right) =>
    left.type.localeCompare(right.type),
  )) {
    let remoteDefinition = definitionsByType.get(definition.type);
    const isInitialPublication =
      !remoteDefinition || (inventory.versionsByDefinitionId[remoteDefinition.id] ?? []).length === 0;
    const categories = categoryResult.byDefinitionType.get(definition.type) ?? [];
    const categoryIds = categories.flatMap((category) => category.id ? [category.id] : []);
    const remoteCategoryIds = remoteDefinition ? getRemoteModuleCategoryIds(remoteDefinition) : [];
    const remoteCategoryGivenIds = remoteCategoryIds.map(
      (categoryId) => categoryResult.byId.get(categoryId)?.givenId ?? categoryId,
    );
    const categoryChanged = categories.length > 0 &&
      (categoryIds.length !== categories.length || !haveSameValues(remoteCategoryIds, categoryIds));
    const shouldPublishDefinitionGlobally =
      (isInitialPublication && definition.global !== false) ||
      (!isInitialPublication && definition.global === true && remoteDefinition?.isGlobalPublished !== true);
    if (!remoteDefinition) {
      items.push(
        createItem(
          definition,
          "create-definition",
          dryRun,
          `Create module definition ${definition.type}.`,
          definition.description,
          createDiff(undefined, {
            type: definition.type,
            name: definition.name,
            description: definition.description,
            ...(categories.length > 0
              ? { moduleCategories: categories.map((category) => category.spec.givenId) }
              : {}),
          }),
        ),
      );
      if (!dryRun) {
        remoteDefinition = await client.createModuleDefinition({
          type: definition.type,
          name: definition.name,
          description: definition.description,
          ...(categoryIds.length > 0 ? { moduleCategoryIds: categoryIds } : {}),
        });
        definitionsByType.set(remoteDefinition.type, remoteDefinition);
        inventory.versionsByDefinitionId[remoteDefinition.id] = [];
      }
    } else if (
      remoteDefinition.name !== definition.name ||
      remoteDefinition.description !== definition.description ||
      categoryChanged
    ) {
      items.push(
        createItem(
          definition,
          "patch-definition",
          dryRun,
          `Patch metadata for module definition ${definition.type}.`,
          definition.description,
          createDiff(
            {
              type: remoteDefinition.type,
              name: remoteDefinition.name,
              description: remoteDefinition.description,
              ...(remoteCategoryGivenIds.length > 0
                ? { moduleCategories: remoteCategoryGivenIds }
                : {}),
            },
            {
              type: definition.type,
              name: definition.name,
              description: definition.description,
              ...(categories.length > 0
                ? { moduleCategories: categories.map((category) => category.spec.givenId) }
                : remoteCategoryGivenIds.length > 0
                  ? { moduleCategories: remoteCategoryGivenIds }
                  : {}),
            },
          ),
        ),
      );
      if (!dryRun) {
        remoteDefinition = await client.patchModuleDefinition({
          ...remoteDefinition,
          name: definition.name,
          description: definition.description,
          ...(categoryIds.length > 0 ? { moduleCategoryIds: categoryIds } : {}),
        });
        definitionsByType.set(remoteDefinition.type, remoteDefinition);
      }
    }

    const latestRemoteVersion = remoteDefinition
      ? selectLatestVersion(inventory.versionsByDefinitionId[remoteDefinition.id] ?? [])
      : undefined;
    const globalPublicationItem = shouldPublishDefinitionGlobally
      ? createItem(
          definition,
          "patch-definition",
          dryRun,
          `Publish module definition ${definition.type} globally.`,
          "Make the module definition available globally.",
          createDiff(
            { isGlobalPublished: false },
            { isGlobalPublished: true },
          ),
          latestRemoteVersion?.version,
        )
      : undefined;

    const remoteVersion = remoteDefinition
      ? (inventory.versionsByDefinitionId[remoteDefinition.id] ?? []).find(
          (version) => version.version === definition.version,
        )
      : undefined;
    if (remoteVersion && remoteDefinition) {
      items.push(
        createItem(
          definition,
          "skip-version",
          dryRun,
          `Skip ${definition.type}@${definition.version}; identical version already exists.`,
          remoteVersion.description,
          undefined,
          remoteVersion.version,
        ),
      );
      if (globalPublicationItem) {
        items.push(globalPublicationItem);
      }
      if (!dryRun && shouldPublishDefinitionGlobally) {
        remoteDefinition = await client.patchModuleDefinition({
          id: remoteDefinition.id,
          isGlobalPublished: true,
        });
        definitionsByType.set(remoteDefinition.type, remoteDefinition);
      }
      continue;
    }

    items.push(
      createItem(
        definition,
        "create-version",
        dryRun,
        `Create module version ${definition.type}@${definition.version}.`,
        definition.releaseDescription,
        createDiff(latestRemoteVersion?.config, definition.module),
        latestRemoteVersion?.version,
      ),
    );
    if (globalPublicationItem) {
      items.push(globalPublicationItem);
    }
    if (!dryRun) {
      if (!remoteDefinition) {
        throw new PublishError(
          `Cannot create ${definition.type}@${definition.version}; module definition was not created.`,
        );
      }
      if (isInitialPublication) {
        await client.dryRunModuleVersion({
          moduleDefinitionId: remoteDefinition.id,
          version: definition.version,
          description: definition.releaseDescription,
          config: definition.module,
        });
      }
      await createVersionOrConfirmDuplicate(client, remoteDefinition.id, definition);
      if (shouldPublishDefinitionGlobally) {
        remoteDefinition = await client.patchModuleDefinition({
          id: remoteDefinition.id,
          isGlobalPublished: true,
        });
        definitionsByType.set(remoteDefinition.type, remoteDefinition);
      }
    }
  }

  return { dryRun, categoryItems: categoryResult.items, items };
}

interface ResolvedModuleCategory {
  spec: ModuleCategorySpec;
  id?: string;
}

interface ModuleCategoryPublishResult {
  items: ModuleCategoryPublishPlanItem[];
  byDefinitionType: Map<string, ResolvedModuleCategory[]>;
  byId: Map<string, RemoteModuleCategory>;
}

async function publishModuleCategories(
  definitions: CompiledDefinition[],
  client: RavionModuleApiClient,
  dryRun: boolean,
  logger?: (message: string) => void,
): Promise<ModuleCategoryPublishResult> {
  const specsByGivenId = new Map<string, ModuleCategorySpec>();
  for (const definition of definitions) {
    for (const spec of getModuleCategoriesForDefinitionType(definition.type)) {
      specsByGivenId.set(spec.givenId, spec);
    }
  }

  if (specsByGivenId.size === 0) {
    return { items: [], byDefinitionType: new Map(), byId: new Map() };
  }

  logger?.("Loading remote module categories from Ravion API.");
  const remoteCategories = await wrapApiStep("list remote module categories", () =>
    client.listModuleCategories(),
  );
  const byId = new Map(remoteCategories.map((category) => [category.id, category]));
  const byDefinitionType = new Map<string, ResolvedModuleCategory[]>();
  const items: ModuleCategoryPublishPlanItem[] = [];

  for (const spec of [...specsByGivenId.values()].sort(
    (left, right) => left.sortOrder - right.sortOrder,
  )) {
    const matchingCategories = remoteCategories.filter(
      (category) =>
        category.givenId === spec.givenId || spec.previousGivenIds?.includes(category.givenId),
    );
    let category = matchingCategories.find((candidate) => candidate.organizationId === undefined) ??
      matchingCategories[0];
    const desiredMetadata = moduleCategoryMetadata(spec);

    if (!category) {
      items.push({
        givenId: spec.givenId,
        action: "create-category",
        dryRun,
        message: `Create and globally publish module category ${spec.givenId}.`,
        diff: createDiff(undefined, { ...desiredMetadata, scope: "global" }),
      });
      if (!dryRun) {
        const createdCategory = await wrapApiStep(`create module category ${spec.givenId}`, () =>
          client.createModuleCategory(desiredMetadata),
        );
        category = await wrapApiStep(`publish module category ${spec.givenId} globally`, () =>
          client.patchModuleCategory({ id: createdCategory.id, isGlobalPublished: true }),
        );
      }
    } else {
      const metadataChanged = category.givenId !== spec.givenId ||
        category.name !== spec.name ||
        category.description !== spec.description ||
        category.sortOrder !== spec.sortOrder;
      const requiresGlobalPublication = category.organizationId !== undefined;
      if (metadataChanged || requiresGlobalPublication) {
        items.push({
          givenId: spec.givenId,
          action: "patch-category",
          dryRun,
          message: `Update module category ${spec.givenId}${requiresGlobalPublication ? " and publish it globally" : ""}.`,
          diff: createDiff(
            {
              givenId: category.givenId,
              name: category.name,
              description: category.description,
              sortOrder: category.sortOrder,
              scope: category.organizationId === undefined ? "global" : "organization",
            },
            { ...desiredMetadata, scope: "global" },
          ),
        });
        if (!dryRun) {
          const categoryId = category.id;
          category = await wrapApiStep(`update module category ${spec.givenId}`, () =>
            client.patchModuleCategory({
              id: categoryId,
              ...desiredMetadata,
              ...(requiresGlobalPublication ? { isGlobalPublished: true } : {}),
            }),
          );
        }
      }
    }

    if (category) {
      byId.set(category.id, category);
    }
    for (const definitionType of spec.definitionTypes) {
      const categories = byDefinitionType.get(definitionType) ?? [];
      categories.push({ spec, id: category?.id });
      byDefinitionType.set(definitionType, categories);
    }
  }

  return { items, byDefinitionType, byId };
}

function moduleCategoryMetadata(spec: ModuleCategorySpec): ModuleCategoryInput {
  return {
    givenId: spec.givenId,
    name: spec.name,
    description: spec.description,
    sortOrder: spec.sortOrder,
  };
}

function getRemoteModuleCategoryIds(definition: RemoteModuleDefinition): string[] {
  if (definition.moduleCategoryIds) {
    return definition.moduleCategoryIds;
  }
  return definition.moduleCategoryId ? [definition.moduleCategoryId] : [];
}

function haveSameValues(left: string[], right: string[]): boolean {
  if (left.length !== right.length) {
    return false;
  }
  const sortedRight = [...right].sort();
  return [...left].sort().every((value, index) => value === sortedRight[index]);
}

export async function dryRunModuleVersions(
  compiledDefinitions: CompiledDefinition[],
  client: RavionModuleApiClient,
  options: ModuleVersionDryRunOptions = {},
): Promise<ModuleVersionDryRunResult[]> {
  const publishedDefinitions = compiledDefinitions.filter((definition) => definition.published);
  if (publishedDefinitions.length === 0) {
    return [];
  }
  const inventory = await loadRemoteInventory(client, { logger: options.logger });
  const definitionsToValidate = options.localDev
    ? applyLocalDevVersions(publishedDefinitions, inventory, options.localDevSourceRef ?? "main", {
        force: options.localDevForce,
      })
    : publishedDefinitions;
  const statuses = getReleaseStatuses(definitionsToValidate, { inventory });
  const results = await Promise.all(
    statuses.map(async (status) => {
      if (status.publishState === "published") {
        return {
          type: status.type,
          version: status.version,
          status: "skipped" as const,
          message: "Release version is already published remotely.",
        };
      }
      if (!status.remoteDefinitionId) {
        return {
          type: status.type,
          version: status.version,
          status: "skipped" as const,
          message: "Remote module definition does not exist yet; no module definition ID is available for dry-run validation.",
        };
      }
      const definition = definitionsToValidate.find((item) => item.type === status.type);
      if (!definition) {
        return {
          type: status.type,
          version: status.version,
          status: "failed" as const,
          message: "Compiled module definition could not be found.",
        };
      }
      try {
        await client.dryRunModuleVersion({
          moduleDefinitionId: status.remoteDefinitionId,
          version: definition.version,
          description: definition.releaseDescription,
          config: definition.module,
        });
        return {
          type: status.type,
          version: status.version,
          status: "validated" as const,
          message: "Module version config passed server-side dry-run validation.",
        };
      } catch (error) {
        return {
          type: status.type,
          version: status.version,
          status: "failed" as const,
          message: formatUnknownError(error),
        };
      }
    }),
  );
  return results.sort((left, right) => left.type.localeCompare(right.type));
}

export async function createDefaultRavionApiClient(
  options: RavionApiClientOptions = {},
): Promise<RavionModuleApiClient> {
  const baseUrl = options.baseUrl ?? process.env.RAVION_API_URL ?? DEFAULT_RAVION_API_URL;
  const token = options.token ?? process.env.RAVION_API_TOKEN;
  if ((options.requireToken ?? true) && !token) {
    throw new PublishError(
      "RAVION_API_TOKEN must be set to read or publish module definitions through the Ravion API.",
    );
  }
  return new HttpRavionModuleApiClient(baseUrl, token);
}

export function applyLocalDevVersions(
  compiledDefinitions: CompiledDefinition[],
  inventory: RemoteModuleInventory,
  sourceRef = "main",
  options: { force?: boolean } = {},
): CompiledDefinition[] {
  const definitionsByType = new Map(
    inventory.definitions.map((definition) => [definition.type, definition]),
  );
  return compiledDefinitions.map((definition) => {
    const remoteDefinition = definitionsByType.get(definition.type);
    const remoteVersions = remoteDefinition
      ? (inventory.versionsByDefinitionId[remoteDefinition.id] ?? [])
      : [];
    const originalTag = `${definition.type}@${definition.version}`;
    const selectedVersion = selectLocalDevVersion(definition, remoteVersions, sourceRef, options);
    const module = replaceLocalDevSourceRefs(definition.module, originalTag, sourceRef) as Record<
      string,
      unknown
    >;
    if (selectedVersion === definition.version) {
      return { ...definition, module };
    }

    return {
      ...definition,
      version: selectedVersion,
      module,
    };
  });
}

export function formatPublishPlanMarkdown(result: PublishResult): string {
  const plannedChanges = result.items.filter((item) => item.action !== "skip-version");
  const categoryChanges = result.categoryItems ?? [];
  const lines = [
    "<!-- ravion-module-publish-plan -->",
    "## Ravion Module Publish Plan",
    "",
    result.dryRun
      ? "Dry run only. No Ravion API mutations were made."
      : "Applied publish changes to the Ravion API.",
    "",
  ];

  if (result.errors && result.errors.length > 0) {
    lines.push(
      "### 🚨 Release Config Conflicts 🚨",
      "",
      "These module versions already exist remotely with different compiled config. Publish a new version, or make the local definition match the existing remote version.",
      "",
    );
    lines.push(
      "| Module | Release Version | Latest Remote Version | Problem |",
      "| --- | --- | --- | --- |",
    );
    for (const error of result.errors) {
      lines.push(
        `| \`${escapeMarkdownTableCell(error.type)}\` | \`${escapeMarkdownTableCell(error.version)}\` | ${error.latestVersion ? `\`${escapeMarkdownTableCell(error.latestVersion)}\`` : "n/a"} | ${escapeMarkdownTableCell(error.message)} |`,
      );
    }

    const errorsWithDiffs = result.errors.filter((error) => error.diff);
    if (errorsWithDiffs.length > 0) {
      lines.push("", "### Latest Remote vs Compiled", "");
      for (const error of errorsWithDiffs) {
        lines.push(
          `#### ${error.type} ${error.latestVersion ?? "n/a"} -> ${error.version}`,
          "",
          "```diff",
          truncateDiff(error.diff ?? ""),
          "```",
          "",
        );
      }
    }

    return lines.join("\n");
  }

  if (result.items.length === 0) {
    lines.push("No module definitions were found.", "");
    return lines.join("\n");
  }

  if (plannedChanges.length === 0 && categoryChanges.length === 0) {
    lines.push(
      "No publish changes are required. All versions already exist with identical config.",
      "",
    );
    return lines.join("\n");
  }

  if (categoryChanges.length > 0) {
    lines.push(
      "### Module Categories",
      "",
      "| Category | Action | Description |",
      "| --- | --- | --- |",
    );
    for (const item of [...categoryChanges].sort((left, right) => left.givenId.localeCompare(right.givenId))) {
      lines.push(
        `| \`${escapeMarkdownTableCell(item.givenId)}\` | \`${item.action}\` | ${escapeMarkdownTableCell(item.message)} |`,
      );
    }
    lines.push("");
  }

  if (plannedChanges.length > 0) {
    lines.push(
      "| Module | Current Version | New Version | Description |",
      "| --- | --- | --- | --- |",
    );
    const byModule = (left: PublishPlanItem, right: PublishPlanItem) =>
      left.type.localeCompare(right.type) || left.version.localeCompare(right.version);
    for (const item of summarizePublishPlanTableItems(plannedChanges).sort(byModule)) {
      lines.push(
        `| \`${escapeMarkdownTableCell(item.type)}\` | ${formatVersionCell(item.currentVersion)} | \`${escapeMarkdownTableCell(item.version)}\` | ${escapeMarkdownTableCell(item.description || item.message)} |`,
      );
    }
  }

  const itemsWithDiffs = plannedChanges.filter((item) => item.diff);
  const categoryItemsWithDiffs = categoryChanges.filter((item) => item.diff);
  if (itemsWithDiffs.length > 0 || categoryItemsWithDiffs.length > 0) {
    lines.push("", "### Diffs", "");
    for (const item of categoryItemsWithDiffs) {
      lines.push(
        `#### Category ${item.givenId}`,
        "",
        "```diff",
        truncateDiff(item.diff ?? ""),
        "```",
        "",
      );
    }
    for (const item of itemsWithDiffs) {
      lines.push(
        `#### ${item.type} ${item.currentVersion ?? "n/a"} -> ${item.version}`,
        "",
        "```diff",
        truncateDiff(item.diff ?? ""),
        "```",
        "",
      );
    }
  }

  return lines.join("\n");
}

export function isPublishPlanError(error: unknown): error is PublishPlanError {
  return error instanceof PublishPlanError;
}

export async function loadRemoteInventory(
  client: RavionModuleApiClient,
  options: { logger?: (message: string) => void } = {},
): Promise<RemoteModuleInventory> {
  options.logger?.("Loading remote module definitions from Ravion API.");
  const definitions = await wrapApiStep("list remote module definitions", () =>
    client.listModuleDefinitions(),
  );
  options.logger?.(`Loading remote module versions for ${definitions.length} definitions.`);
  const versions = await Promise.all(
    definitions.map(async (definition) => {
      const label = `${definition.type} (${definition.id})`;
      return [
        definition.id,
        await wrapApiStep(`list remote module versions for ${label}`, () =>
          client.listModuleVersions(definition.id),
        ),
      ] as const;
    }),
  );
  return { definitions, versionsByDefinitionId: Object.fromEntries(versions) };
}

async function wrapApiStep<T>(label: string, run: () => Promise<T>): Promise<T> {
  try {
    return await run();
  } catch (error) {
    throw new PublishError(`Failed to ${label}: ${formatUnknownError(error)}`);
  }
}

function createPublishPlanErrors(
  statuses: ReleaseStatus[],
  compiledDefinitions: CompiledDefinition[],
  inventory: RemoteModuleInventory,
): PublishPlanErrorItem[] {
  const compiledByType = new Map(
    compiledDefinitions.map((definition) => [definition.type, definition]),
  );
  return statuses
    .filter(
      (status) =>
        status.publishState === "conflict" ||
        (status.publishState === "unpublished" && status.releaseDescription.trim().length === 0),
    )
    .map((status) => {
      const compiled = compiledByType.get(status.type);
      const remoteVersions = status.remoteDefinitionId
        ? (inventory.versionsByDefinitionId[status.remoteDefinitionId] ?? [])
        : [];
      const latestVersion = selectLatestVersion(remoteVersions);
      return {
        type: status.type,
        version: status.version,
        message: status.message,
        latestVersion: latestVersion?.version,
        diff: compiled ? createDiff(latestVersion?.config, compiled.module) : undefined,
      };
    });
}

async function createVersionOrConfirmDuplicate(
  client: RavionModuleApiClient,
  moduleDefinitionId: string,
  definition: CompiledDefinition,
): Promise<void> {
  try {
    await client.createModuleVersion({
      moduleDefinitionId,
      version: definition.version,
      description: definition.releaseDescription,
      config: definition.module,
    });
  } catch (error) {
    if (!isDuplicateVersionError(error)) {
      throw error;
    }
    const duplicateVersion = (await client.listModuleVersions(moduleDefinitionId)).find(
      (version) => version.version === definition.version,
    );
    if (
      !duplicateVersion ||
      stableStringify(duplicateVersion.config) !== stableStringify(definition.module)
    ) {
      throw new PublishError(
        `${definition.type}@${definition.version} already exists remotely with different compiled config.`,
      );
    }
  }
}

function selectLocalDevVersion(
  definition: CompiledDefinition,
  remoteVersions: RemoteModuleVersion[],
  sourceRef: string,
  options: { force?: boolean } = {},
): string {
  for (let suffix = 1; ; suffix += 1) {
    const candidate = `${definition.version}-${suffix}`;
    const remoteVersion = remoteVersions.find((version) => version.version === candidate);
    const candidateModule = replaceLocalDevSourceRefs(
      definition.module,
      `${definition.type}@${definition.version}`,
      sourceRef,
    );
    if (!remoteVersion || (!options.force && stableStringify(remoteVersion.config) === stableStringify(candidateModule))) {
      return candidate;
    }
  }
}

function replaceLocalDevSourceRefs(
  value: unknown,
  originalTag: string,
  replacementTag: string,
): unknown {
  if (Array.isArray(value)) {
    return value.map((item) => replaceLocalDevSourceRefs(item, originalTag, replacementTag));
  }
  if (typeof value === "string") {
    return value.replaceAll(originalTag, replacementTag);
  }
  if (!isRecord(value)) {
    return value;
  }
  const output = Object.fromEntries(
    Object.entries(value).map(([key, child]) => [
      key,
      replaceLocalDevSourceRefs(child, originalTag, replacementTag),
    ]),
  );
  if (
    typeof value.ref === "string" &&
    value.ref.includes(originalTag) &&
    typeof value.branch === "string"
  ) {
    output.branch = replacementTag;
  }
  return output;
}

function createItem(
  definition: CompiledDefinition,
  action: PublishAction,
  dryRun: boolean,
  message: string,
  description: string,
  diff?: string,
  currentVersion?: string,
): PublishPlanItem {
  return {
    type: definition.type,
    version: definition.version,
    currentVersion,
    action,
    dryRun,
    message,
    description,
    diff,
  };
}

function summarizePublishPlanTableItems(items: PublishPlanItem[]): PublishPlanItem[] {
  const rows: PublishPlanItem[] = [];
  for (const item of items) {
    const existingIndex = rows.findIndex(
      (row) => row.type === item.type && row.version === item.version,
    );
    if (existingIndex === -1) {
      rows.push(item);
    } else if (
      rows[existingIndex].action !== "create-version" &&
      item.action === "create-version"
    ) {
      rows[existingIndex] = item;
    }
  }
  return rows;
}

function createDiff(remote: unknown, local: unknown): string | undefined {
  const remoteText = remote === undefined ? "" : stableStringifyYaml(remote);
  const localText = stableStringifyYaml(local);
  if (remoteText === localText) {
    return undefined;
  }

  return createUnifiedDiff(remoteText, localText);
}

function createUnifiedDiff(remoteText: string, localText: string, contextLineCount = 3): string {
  const remoteLines = remoteText.split("\n");
  const localLines = localText.split("\n");
  const operations = diffLines(remoteLines, localLines);
  const changedIndexes = operations.flatMap((operation, index) =>
    operation.type === "equal" ? [] : [index],
  );
  if (changedIndexes.length === 0) {
    return "";
  }

  const selected = new Set<number>();
  for (const index of changedIndexes) {
    for (
      let selectedIndex = Math.max(0, index - contextLineCount);
      selectedIndex <= Math.min(operations.length - 1, index + contextLineCount);
      selectedIndex += 1
    ) {
      selected.add(selectedIndex);
    }
  }

  const lines = ["--- remote", "+++ compiled"];
  let previousIndex = -1;
  for (const index of [...selected].sort((left, right) => left - right)) {
    if (previousIndex >= 0 && index > previousIndex + 1) {
      lines.push("@@");
    }
    const operation = operations[index];
    lines.push(
      `${operation.type === "add" ? "+" : operation.type === "remove" ? "-" : " "}${operation.line}`,
    );
    previousIndex = index;
  }

  return lines.join("\n");
}

function diffLines(
  remoteLines: string[],
  localLines: string[],
): Array<{ type: "equal" | "remove" | "add"; line: string }> {
  const lengths = Array.from({ length: remoteLines.length + 1 }, () =>
    Array<number>(localLines.length + 1).fill(0),
  );
  for (let remoteIndex = remoteLines.length - 1; remoteIndex >= 0; remoteIndex -= 1) {
    for (let localIndex = localLines.length - 1; localIndex >= 0; localIndex -= 1) {
      lengths[remoteIndex][localIndex] =
        remoteLines[remoteIndex] === localLines[localIndex]
          ? lengths[remoteIndex + 1][localIndex + 1] + 1
          : Math.max(lengths[remoteIndex + 1][localIndex], lengths[remoteIndex][localIndex + 1]);
    }
  }

  const operations: Array<{ type: "equal" | "remove" | "add"; line: string }> = [];
  let remoteIndex = 0;
  let localIndex = 0;
  while (remoteIndex < remoteLines.length && localIndex < localLines.length) {
    if (remoteLines[remoteIndex] === localLines[localIndex]) {
      operations.push({ type: "equal", line: remoteLines[remoteIndex] });
      remoteIndex += 1;
      localIndex += 1;
    } else if (lengths[remoteIndex + 1][localIndex] >= lengths[remoteIndex][localIndex + 1]) {
      operations.push({ type: "remove", line: remoteLines[remoteIndex] });
      remoteIndex += 1;
    } else {
      operations.push({ type: "add", line: localLines[localIndex] });
      localIndex += 1;
    }
  }
  while (remoteIndex < remoteLines.length) {
    operations.push({ type: "remove", line: remoteLines[remoteIndex] });
    remoteIndex += 1;
  }
  while (localIndex < localLines.length) {
    operations.push({ type: "add", line: localLines[localIndex] });
    localIndex += 1;
  }

  return operations;
}

function stableStringifyYaml(value: unknown): string {
  return YAML.stringify(sortObjectKeys(value), { lineWidth: 0 }).trimEnd();
}

function selectLatestVersion(versions: RemoteModuleVersion[]): RemoteModuleVersion | undefined {
  return [...versions].sort((left, right) => compareSemver(right.version, left.version))[0];
}

function compareSemver(left: string, right: string): number {
  const leftParsed = parseSemver(left);
  const rightParsed = parseSemver(right);
  for (let index = 0; index < 3; index += 1) {
    const difference = leftParsed.numbers[index] - rightParsed.numbers[index];
    if (difference !== 0) {
      return difference;
    }
  }

  if (leftParsed.prerelease && !rightParsed.prerelease) {
    return -1;
  }
  if (!leftParsed.prerelease && rightParsed.prerelease) {
    return 1;
  }
  return left.localeCompare(right);
}

function parseSemver(version: string): { numbers: [number, number, number]; prerelease?: string } {
  const [core, prerelease] = version.split("-", 2);
  const parts = core.split(".").map((part) => Number.parseInt(part, 10));
  return { numbers: [parts[0] ?? 0, parts[1] ?? 0, parts[2] ?? 0], prerelease };
}

function formatVersionCell(version: string | undefined): string {
  return version ? `\`${escapeMarkdownTableCell(version)}\`` : "n/a";
}

function escapeMarkdownTableCell(value: string): string {
  return value.replace(/\|/g, "\\|").replace(/\n/g, "<br>");
}

function truncateDiff(diff: string): string {
  const maxLength = 12000;
  if (diff.length <= maxLength) {
    return diff;
  }
  return `${diff.slice(0, maxLength)}\n... diff truncated ...`;
}

function isDuplicateVersionError(error: unknown): boolean {
  if (error instanceof HttpApiError && error.status === 409) {
    return true;
  }
  return error instanceof Error && /duplicate|already exists|conflict/i.test(error.message);
}

function stableStringify(value: unknown): string {
  return JSON.stringify(sortObjectKeys(value));
}

function sortObjectKeys(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map((item) => sortObjectKeys(item));
  }
  if (!isRecord(value)) {
    return value;
  }
  return Object.fromEntries(
    Object.keys(value)
      .sort()
      .map((key) => [key, sortObjectKeys(value[key])]),
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

class HttpApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = "HttpApiError";
  }
}

class HttpRavionModuleApiClient implements RavionModuleApiClient {
  private readonly baseUrl: string;

  constructor(
    baseUrl: string,
    private readonly token?: string,
  ) {
    this.baseUrl = baseUrl.replace(/\/$/, "");
  }

  async listModuleCategories(): Promise<RemoteModuleCategory[]> {
    return this.list<RemoteModuleCategory>("/module-categories");
  }

  async createModuleCategory(input: ModuleCategoryInput): Promise<RemoteModuleCategory> {
    return this.call<RemoteModuleCategory>("POST", "/module-categories", { data: input });
  }

  async patchModuleCategory(input: ModuleCategoryPatchInput): Promise<RemoteModuleCategory> {
    return this.call<RemoteModuleCategory>(
      "PATCH",
      `/module-categories/${encodeURIComponent(input.id)}`,
      {
        data: {
          givenId: input.givenId,
          name: input.name,
          description: input.description,
          icon: input.icon,
          sortOrder: input.sortOrder,
          isGlobalPublished: input.isGlobalPublished,
        },
      },
    );
  }

  async listModuleDefinitions(): Promise<RemoteModuleDefinition[]> {
    return this.list<RemoteModuleDefinition>("/module-definitions");
  }

  async createModuleDefinition(input: ModuleDefinitionInput): Promise<RemoteModuleDefinition> {
    return this.call<RemoteModuleDefinition>("POST", "/module-definitions", { data: input });
  }

  async patchModuleDefinition(input: ModuleDefinitionPatchInput): Promise<RemoteModuleDefinition> {
    return this.call<RemoteModuleDefinition>(
      "PATCH",
      `/module-definitions/${encodeURIComponent(input.id)}`,
      {
        data: {
          name: input.name,
          description: input.description,
          moduleCategoryIds: input.moduleCategoryIds,
          isGlobalPublished: input.isGlobalPublished,
        },
      },
    );
  }

  async listModuleVersions(moduleDefinitionId: string): Promise<RemoteModuleVersion[]> {
    return this.list<RemoteModuleVersion>("/module-versions", { moduleDefinitionId });
  }

  async createModuleVersion(input: ModuleVersionInput): Promise<RemoteModuleVersion> {
    return this.call<RemoteModuleVersion>("POST", "/module-versions", { data: input });
  }

  async dryRunModuleVersion(input: ModuleVersionInput): Promise<ModuleVersionDryRunResponse> {
    return this.call<ModuleVersionDryRunResponse>("POST", "/module-versions", {
      data: { ...input, dryRun: true },
    });
  }

  private async list<T>(path: string, query: Record<string, string> = {}): Promise<T[]> {
    const items: T[] = [];
    let cursor: string | undefined;

    do {
      const response = await this.call<{ data: T[]; meta?: { nextCursor?: string } }>(
        "GET",
        path,
        undefined,
        { ...query, limit: "100", ...(cursor ? { cursor } : {}) },
        { unwrap: false },
      );
      items.push(...response.data);
      cursor = response.meta?.nextCursor;
    } while (cursor);

    return items;
  }

  private async call<T>(
    method: string,
    path: string,
    input?: unknown,
    query: Record<string, string> = {},
    options: { unwrap?: boolean } = {},
  ): Promise<T> {
    const headers: Record<string, string> = { "Content-Type": "application/json" };
    if (this.token) {
      headers.Authorization = `Bearer ${this.token}`;
    }

    const url = buildUrl(this.baseUrl, path, query);
    let response: Response;
    try {
      response = await fetch(url, {
        method,
        headers,
        body: input === undefined ? undefined : JSON.stringify(input),
      });
    } catch (error) {
      throw new PublishError(
        `Ravion API request failed before receiving a response: ${method} ${url}: ${formatUnknownError(error)}`,
      );
    }
    const payload = await readResponsePayload(response);
    if (!response.ok) {
      const message = extractErrorMessage(payload, "No response error message was returned.");
      throw new HttpApiError(
        response.status,
        `${method} ${url} failed with HTTP ${response.status}: ${message}\nResponse body:\n${formatResponsePayload(payload)}`,
      );
    }
    return (options.unwrap === false ? payload : unwrapApiPayload(payload)) as T;
  }
}

function buildUrl(baseUrl: string, path: string, query: Record<string, string>): string {
  const url = new URL(`${baseUrl}${path}`);
  for (const [key, value] of Object.entries(query)) {
    url.searchParams.set(key, value);
  }
  return url.toString();
}

async function readResponsePayload(response: Response): Promise<unknown> {
  const text = await response.text();
  if (text.trim().length === 0) {
    return undefined;
  }
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

function unwrapApiPayload(payload: unknown): unknown {
  if (!isRecord(payload)) {
    return payload;
  }
  if ("result" in payload) {
    const result = payload.result;
    return isRecord(result) && "data" in result ? result.data : result;
  }
  if ("data" in payload) {
    return payload.data;
  }
  return payload;
}

function extractErrorMessage(payload: unknown, fallback: string): string {
  if (isRecord(payload)) {
    const parts = [];
    if (typeof payload.code === "string") {
      parts.push(`code=${payload.code}`);
    }
    if (typeof payload.message === "string") {
      parts.push(payload.message);
    }
    if (typeof payload.description === "string") {
      parts.push(payload.description);
    }
    if (typeof payload.requestId === "string") {
      parts.push(`requestId=${payload.requestId}`);
    }
    if (parts.length > 0) {
      return parts.join("; ");
    }
    if (isRecord(payload.error)) {
      return extractErrorMessage(payload.error, fallback);
    }
  }
  return typeof payload === "string" && payload.length > 0 ? payload : fallback;
}

function formatResponsePayload(payload: unknown): string {
  if (typeof payload === "string") {
    return payload;
  }
  return JSON.stringify(payload, null, 2);
}

function formatUnknownError(error: unknown): string {
  if (error instanceof Error) {
    return `${error.name}: ${error.message}`;
  }
  return String(error);
}
