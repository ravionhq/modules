import { dirname, relative } from "node:path";
import { type CompiledDefinition } from "./compiler.js";
import { type RemoteModuleInventory } from "./generate-definitions.js";

export type ReleasePublishState = "disabled" | "unknown" | "unpublished" | "published" | "conflict";

export interface ReleaseStatus {
  type: string;
  name: string;
  version: string;
  releaseDescription: string;
  filePath: string;
  modulePath: string;
  publishState: ReleasePublishState;
  remoteDefinitionId?: string;
  message: string;
}

export class ReleaseMetadataError extends Error {
  readonly statuses: ReleaseStatus[];

  constructor(statuses: ReleaseStatus[]) {
    super(formatStatusErrors(statuses));
    this.name = "ReleaseMetadataError";
    this.statuses = statuses;
  }
}

export function getReleaseStatuses(
  compiledDefinitions: CompiledDefinition[],
  options: { inventory?: RemoteModuleInventory; rootPath?: string } = {},
): ReleaseStatus[] {
  return compiledDefinitions.map((definition) => getReleaseStatus(definition, options)).sort((left, right) => left.type.localeCompare(right.type));
}

export function validateReleaseStatuses(statuses: ReleaseStatus[]): void {
  const invalidStatuses = statuses.filter(
    (status) => status.publishState === "conflict" || (status.publishState === "unpublished" && status.releaseDescription.trim().length === 0),
  );
  if (invalidStatuses.length > 0) {
    throw new ReleaseMetadataError(invalidStatuses);
  }
}

function getReleaseStatus(definition: CompiledDefinition, options: { inventory?: RemoteModuleInventory; rootPath?: string }): ReleaseStatus {
  const modulePath = relative(options.rootPath ?? process.cwd(), dirname(definition.filePath));
  const baseStatus = {
    type: definition.type,
    name: definition.name,
    version: definition.version,
    releaseDescription: definition.releaseDescription,
    filePath: definition.filePath,
    modulePath,
  };

  if (!definition.published) {
    return { ...baseStatus, publishState: "disabled", message: "Publication is disabled in the authoring definition." };
  }

  if (!options.inventory) {
    return { ...baseStatus, publishState: "unknown", message: "No remote inventory was provided." };
  }

  const remoteDefinition = options.inventory.definitions.find((item) => item.type === definition.type);
  if (!remoteDefinition) {
    return { ...baseStatus, publishState: "unpublished", message: "Remote module definition does not exist yet." };
  }

  const remoteVersions = options.inventory.versionsByDefinitionId[remoteDefinition.id] ?? [];
  const remoteVersion = remoteVersions.find((item) => item.version === definition.version);
  if (!remoteVersion) {
    return {
      ...baseStatus,
      publishState: "unpublished",
      remoteDefinitionId: remoteDefinition.id,
      message: "Release version does not exist remotely yet.",
    };
  }

  if (stableStringify(remoteVersion.config) !== stableStringify(definition.module)) {
    return {
      ...baseStatus,
      publishState: "conflict",
      remoteDefinitionId: remoteDefinition.id,
      message: "Release version already exists remotely with different compiled config.",
    };
  }

  return {
    ...baseStatus,
    publishState: "published",
    remoteDefinitionId: remoteDefinition.id,
    message: "Release version already exists remotely with identical compiled config.",
  };
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

  return Object.fromEntries(Object.keys(value).sort().map((key) => [key, sortObjectKeys(value[key])]));
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function formatStatusErrors(statuses: ReleaseStatus[]): string {
  const formatted = statuses.map((status) => `- ${status.type}@${status.version}: ${status.message}`).join("\n");
  return `Release metadata validation failed:\n${formatted}`;
}
