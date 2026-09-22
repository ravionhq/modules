import { mkdir, readdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join, relative, resolve } from "node:path";
import YAML from "yaml";

export interface RemoteModuleDefinition {
  id: string;
  organizationId?: string;
  type: string;
  name: string;
  description: string;
  moduleCategoryIds?: string[];
  moduleCategoryId?: string | null;
  isGlobalPublished?: boolean;
}

export interface RemoteModuleVersion {
  moduleDefinitionId: string;
  version: string;
  description: string;
  config: Record<string, unknown>;
}

export interface RemoteModuleInventory {
  definitions: RemoteModuleDefinition[];
  versionsByDefinitionId: Record<string, RemoteModuleVersion[]>;
}

export interface GeneratedDefinitionResult {
  type: string;
  filePath: string;
  modulePath: string;
  version: string;
  content: string;
}

export interface MissingModuleResult {
  type: string;
  expectedModulePath?: string;
  reason: string;
}

export interface GenerateDefinitionsResult {
  generated: GeneratedDefinitionResult[];
  missing: MissingModuleResult[];
}

const REPO_URL = "https://github.com/ravionhq/modules";
const DEFAULT_MODULE_PATHS: Record<string, string> = {
  "rvn-acm-certificate": "security/acm_certificate",
  "rvn-aws-network": "networking/vpc",
  "rvn-aws-rds": "database/rds",
  "rvn-ecs-cluster": "compute/ecs_cluster",
  "rvn-ecs-nlb": "compute/ecs_service",
  "rvn-ecs-web": "compute/ecs_service",
  "rvn-static": "hosting/static_site",
  "rvn-stack": "stack/terraform",
};

export async function generateDefinitionsFromInventory(
  inventory: RemoteModuleInventory,
  rootPath = process.cwd(),
  options: { write?: boolean; modulePaths?: Record<string, string> } = {},
): Promise<GenerateDefinitionsResult> {
  const root = resolve(rootPath);
  const modulePaths = { ...DEFAULT_MODULE_PATHS, ...options.modulePaths };
  const moduleDirectories = await findModuleDirectories(root);
  const generated: GeneratedDefinitionResult[] = [];
  const missing: MissingModuleResult[] = [];

  for (const definition of inventory.definitions.filter((item) => item.type.startsWith("rvn-")).sort((left, right) => left.type.localeCompare(right.type))) {
    const modulePath = modulePaths[definition.type];
    if (!modulePath || !moduleDirectories.has(modulePath)) {
      missing.push({ type: definition.type, expectedModulePath: modulePath, reason: "No matching Terraform module directory exists." });
      continue;
    }

    const latestVersion = selectLatestVersion(inventory.versionsByDefinitionId[definition.id] ?? []);
    if (!latestVersion) {
      missing.push({ type: definition.type, expectedModulePath: modulePath, reason: "No remote module versions were found." });
      continue;
    }

    const module = normalizeSourceRefs(latestVersion.config, modulePath);
    const authoringDefinition = {
      definition: {
        type: definition.type,
        name: definition.name,
        description: definition.description,
      },
      release: {
        version: latestVersion.version,
        description: latestVersion.description,
      },
      module,
    };
    const filePath = join(root, modulePath, `${definition.type}-definition.yml`);
    const content = YAML.stringify(authoringDefinition, { lineWidth: 0 });

    if (options.write) {
      await mkdir(dirname(filePath), { recursive: true });
      await writeFile(filePath, content);
    }

    generated.push({ type: definition.type, filePath, modulePath, version: latestVersion.version, content });
  }

  return { generated, missing };
}

export async function readInventoryFile(filePath: string): Promise<RemoteModuleInventory> {
  const content = await readFile(filePath, "utf8");
  return JSON.parse(content) as RemoteModuleInventory;
}

export function normalizeSourceRefs(value: unknown, modulePath: string): unknown {
  if (Array.isArray(value)) {
    return value.map((item) => normalizeSourceRefs(item, modulePath));
  }

  if (!isRecord(value)) {
    return value;
  }

  const normalized = Object.fromEntries(Object.entries(value).map(([key, child]) => [key, normalizeSourceRefs(child, modulePath)]));
  if (normalized.repo === REPO_URL && normalized.base_path === modulePath && typeof normalized.ref === "string") {
    normalized.ref = "$local.module_tag";
  }

  return normalized;
}

export function normalizeRemoteConfigForComparison(value: unknown, moduleType: string, version: string, modulePath: string): unknown {
  return replaceLocalModuleTag(normalizeSourceRefs(value, modulePath), `${moduleType}@${version}`);
}

function replaceLocalModuleTag(value: unknown, moduleTag: string): unknown {
  if (Array.isArray(value)) {
    return value.map((item) => replaceLocalModuleTag(item, moduleTag));
  }

  if (value === "$local.module_tag") {
    return moduleTag;
  }

  if (!isRecord(value)) {
    return value;
  }

  return Object.fromEntries(Object.entries(value).map(([key, child]) => [key, replaceLocalModuleTag(child, moduleTag)]));
}

async function findModuleDirectories(rootPath: string): Promise<Set<string>> {
  const directories = new Set<string>();
  await collectModuleDirectories(rootPath, rootPath, directories);
  return directories;
}

async function collectModuleDirectories(rootPath: string, directoryPath: string, directories: Set<string>): Promise<void> {
  let entries;
  try {
    entries = await readdir(directoryPath, { withFileTypes: true });
  } catch (error) {
    if (isNodeError(error) && error.code === "ENOENT") {
      return;
    }
    throw error;
  }

  if (entries.some((entry) => entry.isFile() && (entry.name === "versions.tf" || entry.name.endsWith("-definition.yml")))) {
    directories.add(relative(rootPath, directoryPath));
    return;
  }

  for (const entry of entries) {
    if (entry.isDirectory() && !entry.name.startsWith(".") && entry.name !== "node_modules" && entry.name !== "dist") {
      await collectModuleDirectories(rootPath, join(directoryPath, entry.name), directories);
    }
  }
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

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isNodeError(error: unknown): error is NodeJS.ErrnoException {
  return error instanceof Error && "code" in error;
}
