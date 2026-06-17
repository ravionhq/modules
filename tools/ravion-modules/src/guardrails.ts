import { readdir, readFile } from "node:fs/promises";
import { basename, join, relative, resolve, sep } from "node:path";
import YAML from "yaml";
import type { CompiledDefinition } from "./compiler.js";

export class GuardrailError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "GuardrailError";
  }
}

const MODULE_CATEGORIES = new Set([
  "cache",
  "cdn",
  "compute",
  "database",
  "hosting",
  "kubernetes",
  "messaging",
  "modules_without_stack",
  "monitoring",
  "networking",
  "security",
  "storage",
]);

const EXCLUDED_DIRECTORIES = new Set([".git", "node_modules", "dist"]);

export async function runMigrationGuardrails(rootPath = process.cwd()): Promise<void> {
  const root = resolve(rootPath);
  const legacyFiles = await findLegacyModuleDefinitionFiles(root);
  if (legacyFiles.length > 0) {
    throw new GuardrailError(`Legacy module definition YAML files are not allowed:\n${legacyFiles.map((filePath) => `- ${filePath}`).join("\n")}`);
  }
}

export function validateUniqueDefinitionTypes(definitions: CompiledDefinition[]): void {
  const firstFileByType = new Map<string, string>();
  const duplicates: string[] = [];

  for (const definition of definitions) {
    const existingFilePath = firstFileByType.get(definition.type);
    if (existingFilePath) {
      duplicates.push(`${definition.type}: ${existingFilePath} and ${definition.filePath}`);
    } else {
      firstFileByType.set(definition.type, definition.filePath);
    }
  }

  if (duplicates.length > 0) {
    throw new GuardrailError(`Duplicate definition.type values are not allowed:\n${duplicates.map((duplicate) => `- ${duplicate}`).join("\n")}`);
  }
}

async function findLegacyModuleDefinitionFiles(rootPath: string): Promise<string[]> {
  const yamlFiles: string[] = [];
  await collectYamlFiles(rootPath, rootPath, yamlFiles);

  const legacyFiles: string[] = [];
  for (const filePath of yamlFiles) {
    if (isAllowedColocatedDefinition(rootPath, filePath)) {
      continue;
    }

    if (await looksLikeModuleDefinitionFile(filePath)) {
      legacyFiles.push(filePath);
    }
  }

  return legacyFiles.sort((left, right) => left.localeCompare(right));
}

async function collectYamlFiles(rootPath: string, directoryPath: string, files: string[]): Promise<void> {
  let entries;
  try {
    entries = await readdir(directoryPath, { withFileTypes: true });
  } catch (error) {
    if (isNodeError(error) && error.code === "ENOENT") {
      return;
    }
    throw error;
  }

  for (const entry of entries) {
    const entryPath = join(directoryPath, entry.name);
    if (entry.isDirectory()) {
      if (shouldSkipDirectory(rootPath, entryPath, entry.name)) {
        continue;
      }
      await collectYamlFiles(rootPath, entryPath, files);
    } else if (entry.isFile() && isYamlFile(entry.name)) {
      files.push(entryPath);
    }
  }
}

function shouldSkipDirectory(rootPath: string, directoryPath: string, directoryName: string): boolean {
  if (EXCLUDED_DIRECTORIES.has(directoryName)) {
    return true;
  }

  const relativePath = normalizeRelativePath(rootPath, directoryPath);
  return relativePath === "tools/ravion-modules/test/fixtures" || relativePath.startsWith("tools/ravion-modules/test/fixtures/");
}

async function looksLikeModuleDefinitionFile(filePath: string): Promise<boolean> {
  let parsed: unknown;
  try {
    parsed = YAML.parse(await readFile(filePath, "utf8"));
  } catch {
    return false;
  }

  if (!isRecord(parsed)) {
    return false;
  }

  if (isRecord(parsed.definition) && "module" in parsed) {
    return true;
  }

  return typeof parsed.type === "string" && typeof parsed.name === "string" && ("module" in parsed || "config" in parsed || "inputs" in parsed || "stack" in parsed);
}

function isAllowedColocatedDefinition(rootPath: string, filePath: string): boolean {
  if (!isDefinitionFileName(basename(filePath))) {
    return false;
  }

  const [category] = normalizeRelativePath(rootPath, filePath).split("/");
  return MODULE_CATEGORIES.has(category);
}

function isDefinitionFileName(fileName: string): boolean {
  return fileName.endsWith("-definition.yml");
}

function isYamlFile(fileName: string): boolean {
  return fileName.endsWith(".yml") || fileName.endsWith(".yaml");
}

function normalizeRelativePath(rootPath: string, filePath: string): string {
  return relative(rootPath, filePath).split(sep).join("/");
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isNodeError(error: unknown): error is NodeJS.ErrnoException {
  return error instanceof Error && "code" in error;
}
