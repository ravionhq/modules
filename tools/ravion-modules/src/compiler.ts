import { readdir, readFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import YAML from "yaml";
import { parseAuthoringDefinitionFile, type AuthoringDefinition } from "./authoring-schema.js";
import { validateUniqueDefinitionTypes } from "./guardrails.js";

export interface CompiledDefinition {
  filePath: string;
  type: string;
  name: string;
  description: string;
  version: string;
  releaseDescription: string;
  module: Record<string, unknown>;
}

export class CompileError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "CompileError";
  }
}

const DIRECTIVE_KEYS = new Set(["$include", "$merge", "$template"]);
const LOCAL_TOKEN_PATTERN = /\$local\.[A-Za-z0-9_.-]+/g;
const WITH_TOKEN_PATTERN = /^\$with\.([A-Za-z0-9_.-]+)$/;
const WITH_TOKEN_LEAK_PATTERN = /\$with\.[A-Za-z0-9_.-]+/;
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

interface CompileContext {
  definition: AuthoringDefinition;
  sourceFilePath: string;
  includeStack: string[];
}

export async function compileDefinitionFile(filePath: string): Promise<CompiledDefinition> {
  const absoluteFilePath = resolve(filePath);
  const definition = await parseAuthoringDefinitionFile(absoluteFilePath);
  const context: CompileContext = {
    definition,
    sourceFilePath: absoluteFilePath,
    includeStack: [absoluteFilePath],
  };
  const module = await resolveValue(definition.module, context, "module", absoluteFilePath);

  if (!isRecord(module)) {
    throw new CompileError(`${absoluteFilePath}: module compiled to a non-object value.`);
  }

  rejectLeakedCompilerSyntax(module, absoluteFilePath, "module");

  return {
    filePath: absoluteFilePath,
    type: definition.definition.type,
    name: definition.definition.name,
    description: definition.definition.description,
    version: definition.release.version,
    releaseDescription: definition.release.description,
    module,
  };
}

export async function compileAllDefinitions(rootPath = process.cwd()): Promise<CompiledDefinition[]> {
  const definitionFiles = await findDefinitionFiles(resolve(rootPath));
  const compiled = await Promise.all(definitionFiles.map((filePath) => compileDefinitionFile(filePath)));
  const sorted = compiled.sort((left, right) => left.filePath.localeCompare(right.filePath));
  validateUniqueDefinitionTypes(sorted);
  return sorted;
}

async function resolveValue(value: unknown, context: CompileContext, yamlPath: string, currentFilePath: string): Promise<unknown> {
  if (Array.isArray(value)) {
    const resolvedItems: unknown[] = [];
    for (const [index, item] of value.entries()) {
      const resolved = await resolveValue(item, context, `${yamlPath}[${index}]`, currentFilePath);
      if (isDirectiveRecord(item, "$include") || isDirectiveRecord(item, "$template")) {
        if (Array.isArray(resolved)) {
          resolvedItems.push(...resolved);
        } else {
          resolvedItems.push(resolved);
        }
      } else {
        resolvedItems.push(resolved);
      }
    }
    return resolvedItems;
  }

  if (typeof value === "string") {
    return resolveScalar(value, context);
  }

  if (!isRecord(value)) {
    return value;
  }

  if ("$include" in value) {
    return resolveInclude(value.$include, context, `${yamlPath}.$include`, currentFilePath);
  }

  if ("$template" in value) {
    return resolveTemplate(value, context, yamlPath, currentFilePath);
  }

  const merged = new Map<string, unknown>();
  if ("$merge" in value) {
    const mergeValues = Array.isArray(value.$merge) ? value.$merge : [value.$merge];
    for (const [index, mergeValue] of mergeValues.entries()) {
      const resolved = await resolveMergeValue(mergeValue, context, `${yamlPath}.$merge[${index}]`, currentFilePath);
      if (!isRecord(resolved)) {
        throw new CompileError(`${currentFilePath} ${yamlPath}.$merge[${index}]: $merge entries must compile to objects.`);
      }
      for (const [key, child] of Object.entries(resolved)) {
        merged.set(key, child);
      }
    }
  }

  for (const [key, child] of Object.entries(value)) {
    if (key === "$merge") {
      continue;
    }
    merged.set(key, await resolveValue(child, context, `${yamlPath}.${key}`, currentFilePath));
  }

  return Object.fromEntries(merged);
}

async function resolveInclude(includePath: unknown, context: CompileContext, yamlPath: string, currentFilePath: string): Promise<unknown> {
  if (typeof includePath !== "string" || includePath.trim().length === 0) {
    throw new CompileError(`${currentFilePath} ${yamlPath}: $include must be a non-empty string.`);
  }

  const includedFilePath = resolve(dirname(currentFilePath), includePath);
  return resolveExternalFile(includedFilePath, context, yamlPath);
}

async function resolveTemplate(value: Record<string, unknown>, context: CompileContext, yamlPath: string, currentFilePath: string): Promise<unknown> {
  if (typeof value.$template !== "string" || value.$template.trim().length === 0) {
    throw new CompileError(`${currentFilePath} ${yamlPath}.$template: $template must be a non-empty string.`);
  }
  const templateFilePath = resolve(dirname(currentFilePath), value.$template);
  const template = await resolveExternalFile(templateFilePath, context, `${yamlPath}.$template`, false);
  return resolveValue(renderTemplate(template, isRecord(value.with) ? value.with : {}, templateFilePath, yamlPath), context, yamlPath, templateFilePath);
}

async function resolveMergeValue(value: unknown, context: CompileContext, yamlPath: string, currentFilePath: string): Promise<unknown> {
  if (typeof value === "string") {
    return resolveInclude(value, context, yamlPath, currentFilePath);
  }

  return resolveValue(value, context, yamlPath, currentFilePath);
}

async function resolveExternalFile(filePath: string, context: CompileContext, yamlPath: string, resolveDirectives = true): Promise<unknown> {
  if (context.includeStack.includes(filePath)) {
    const chain = [...context.includeStack, filePath].join(" -> ");
    throw new CompileError(`${context.sourceFilePath} ${yamlPath}: include cycle detected: ${chain}`);
  }

  let parsed: unknown;
  try {
    parsed = YAML.parse(await readFile(filePath, "utf8"));
  } catch (error) {
    throw new CompileError(`${context.sourceFilePath} ${yamlPath}: failed to read ${filePath}: ${formatUnknownError(error)}`);
  }

  if (!resolveDirectives) {
    return parsed;
  }

  context.includeStack.push(filePath);
  try {
    return await resolveValue(parsed, context, "<included>", filePath);
  } finally {
    context.includeStack.pop();
  }
}

function resolveScalar(value: string, context: CompileContext): unknown {
  return value.replaceAll("$local.module_tag", `${context.definition.definition.type}@${context.definition.release.version}`);
}

function renderTemplate(value: unknown, parameters: Record<string, unknown>, filePath: string, yamlPath: string): unknown {
  if (Array.isArray(value)) {
    return value.map((item, index) => renderTemplate(item, parameters, filePath, `${yamlPath}[${index}]`));
  }

  if (typeof value === "string") {
    const match = value.match(WITH_TOKEN_PATTERN);
    if (match) {
      return getParameter(parameters, match[1], filePath, yamlPath);
    }

    if (WITH_TOKEN_LEAK_PATTERN.test(value)) {
      throw new CompileError(`${filePath} ${yamlPath}: $with tokens must occupy the entire string.`);
    }

    return value;
  }

  if (!isRecord(value)) {
    return value;
  }

  return Object.fromEntries(
    Object.entries(value).map(([key, child]) => [key, renderTemplate(child, parameters, filePath, `${yamlPath}.${key}`)]),
  );
}

function getParameter(parameters: Record<string, unknown>, path: string, filePath: string, yamlPath: string): unknown {
  let current: unknown = parameters;
  for (const part of path.split(".")) {
    if (!isRecord(current) || !(part in current)) {
      throw new CompileError(`${filePath} ${yamlPath}: template parameter ${path} was not provided.`);
    }
    current = current[part];
  }
  return current;
}

function rejectLeakedCompilerSyntax(value: unknown, filePath: string, yamlPath: string): void {
  if (Array.isArray(value)) {
    value.forEach((item, index) => rejectLeakedCompilerSyntax(item, filePath, `${yamlPath}[${index}]`));
    return;
  }

  if (typeof value === "string") {
    const unresolvedLocalTokens = value.match(LOCAL_TOKEN_PATTERN);
    if (unresolvedLocalTokens) {
      throw new CompileError(`${filePath} ${yamlPath}: unresolved local token ${unresolvedLocalTokens[0]}.`);
    }
    if (WITH_TOKEN_LEAK_PATTERN.test(value)) {
      throw new CompileError(`${filePath} ${yamlPath}: unresolved template token.`);
    }
    return;
  }

  if (!isRecord(value)) {
    return;
  }

  for (const [key, child] of Object.entries(value)) {
    if (DIRECTIVE_KEYS.has(key)) {
      throw new CompileError(`${filePath} ${yamlPath}.${key}: unresolved composition directive.`);
    }
    rejectLeakedCompilerSyntax(child, filePath, `${yamlPath}.${key}`);
  }
}

export async function findDefinitionFiles(rootPath: string): Promise<string[]> {
  const files: string[] = [];
  for (const category of MODULE_CATEGORIES) {
    await collectDefinitionFiles(join(rootPath, category), files);
  }
  return files;
}

async function collectDefinitionFiles(directoryPath: string, files: string[]): Promise<void> {
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
      await collectDefinitionFiles(entryPath, files);
    } else if (entry.isFile() && isDefinitionFileName(entry.name)) {
      files.push(entryPath);
    }
  }
}

function isDefinitionFileName(fileName: string): boolean {
  return fileName.endsWith("-definition.yml");
}

function isDirectiveRecord(value: unknown, directive: "$include" | "$template"): value is Record<string, unknown> {
  return isRecord(value) && Object.keys(value).length <= 2 && directive in value;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isNodeError(error: unknown): error is NodeJS.ErrnoException {
  return error instanceof Error && "code" in error;
}

function formatUnknownError(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
