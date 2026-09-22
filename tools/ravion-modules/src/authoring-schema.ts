import { readFile } from "node:fs/promises";
import YAML from "yaml";

export interface AuthoringDefinition {
  published: boolean;
  global?: boolean;
  definition: {
    type: string;
    name: string;
    description: string;
  };
  release: {
    version: string;
    description: string;
  };
  module: Record<string, unknown>;
}

export interface ValidationIssue {
  path: string;
  message: string;
}

export class AuthoringSchemaError extends Error {
  readonly issues: ValidationIssue[];

  constructor(filePath: string, issues: ValidationIssue[]) {
    super(formatIssues(filePath, issues));
    this.name = "AuthoringSchemaError";
    this.issues = issues;
  }
}

const MODULE_TYPE_PATTERN = /^[a-z][a-z0-9-]*$/;
const SEMVER_PATTERN = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$/;
const ROOT_KEYS = new Set(["published", "global", "definition", "release", "module"]);

export async function parseAuthoringDefinitionFile(filePath: string): Promise<AuthoringDefinition> {
  const content = await readFile(filePath, "utf8");
  const parsed = YAML.parse(content) as unknown;

  return validateAuthoringDefinition(parsed, filePath);
}

export function validateAuthoringDefinition(value: unknown, filePath = "*-definition.yml"): AuthoringDefinition {
  const issues: ValidationIssue[] = [];

  if (!isRecord(value)) {
    throw new AuthoringSchemaError(filePath, [{ path: "$", message: "Definition file must contain a YAML object." }]);
  }

  for (const key of Object.keys(value)) {
    if (!ROOT_KEYS.has(key)) {
      issues.push({ path: key, message: "Only published, global, definition, release, and module are allowed at the root." });
    }
  }

  if (value.published !== undefined && typeof value.published !== "boolean") {
    issues.push({ path: "published", message: "Field must be a boolean when provided." });
  }

  if (value.global !== undefined && typeof value.global !== "boolean") {
    issues.push({ path: "global", message: "Field must be a boolean when provided." });
  }

  const definition = requireRecord(value.definition, "definition", issues);
  if (definition) {
    requireNonEmptyString(definition.type, "definition.type", issues);
    requireNonEmptyString(definition.name, "definition.name", issues);
    requireNonEmptyString(definition.description, "definition.description", issues);

    if (typeof definition.type === "string" && !MODULE_TYPE_PATTERN.test(definition.type)) {
      issues.push({ path: "definition.type", message: "Definition type must use lowercase kebab-case." });
    }
  }

  const release = requireRecord(value.release, "release", issues);
  if (release) {
    requireNonEmptyString(release.version, "release.version", issues);
    requireNonEmptyString(release.description, "release.description", issues);

    if (typeof release.version === "string" && !SEMVER_PATTERN.test(release.version)) {
      issues.push({ path: "release.version", message: "Release version must be a semantic version without a leading v." });
    }
  }

  const module = requireRecord(value.module, "module", issues);
  if (module) {
    validateCompositionDirectives(module, "module", issues);
    validateOptionalSource(module, "module", issues);
  }

  if (issues.length > 0) {
    throw new AuthoringSchemaError(filePath, issues);
  }

  return {
    published: value.published !== false,
    global: value.global as boolean | undefined,
    definition: value.definition as AuthoringDefinition["definition"],
    release: value.release as AuthoringDefinition["release"],
    module: value.module as AuthoringDefinition["module"],
  };
}

function requireRecord(value: unknown, path: string, issues: ValidationIssue[]): Record<string, unknown> | undefined {
  if (!isRecord(value)) {
    issues.push({ path, message: "Field is required and must be an object." });
    return undefined;
  }

  return value;
}

function requireNonEmptyString(value: unknown, path: string, issues: ValidationIssue[]): void {
  if (typeof value !== "string" || value.trim().length === 0) {
    issues.push({ path, message: "Field is required and must be a non-empty string." });
  }
}

function validateCompositionDirectives(value: unknown, path: string, issues: ValidationIssue[]): void {
  if (Array.isArray(value)) {
    value.forEach((item, index) => validateCompositionDirectives(item, `${path}[${index}]`, issues));
    return;
  }

  if (!isRecord(value)) {
    return;
  }

  if ("$include" in value) {
    if (Object.keys(value).length !== 1) {
      issues.push({ path, message: "$include directives cannot have sibling keys." });
    }
    requireNonEmptyString(value.$include, `${path}.$include`, issues);
  }

  if ("$template" in value) {
    const keys = Object.keys(value);
    if (keys.some((key) => key !== "$template" && key !== "with")) {
      issues.push({ path, message: "$template directives can only include a with object." });
    }
    requireNonEmptyString(value.$template, `${path}.$template`, issues);
    if ("with" in value && !isRecord(value.with)) {
      issues.push({ path: `${path}.with`, message: "Template parameters must be an object." });
    }
  }

  if ("$merge" in value) {
    if (!isMergeValue(value.$merge)) {
      issues.push({ path: `${path}.$merge`, message: "$merge must be a non-empty string, object, or array of strings/objects." });
    }
  }

  for (const [key, child] of Object.entries(value)) {
    if (key === "$include" || key === "$template" || key === "$merge") {
      continue;
    }
    validateCompositionDirectives(child, `${path}.${key}`, issues);
  }
}

function validateOptionalSource(module: Record<string, unknown>, path: string, issues: ValidationIssue[]): void {
  const stack = module.stack;
  if (!isRecord(stack) || !("source" in stack)) {
    return;
  }

  const sourcePath = `${path}.stack.source`;
  const source = stack.source;
  if (!isRecord(source)) {
    issues.push({ path: sourcePath, message: "Stack source must be an object when provided." });
    return;
  }

  requireNonEmptyString(source.repo, `${sourcePath}.repo`, issues);
  requireNonEmptyString(source.ref, `${sourcePath}.ref`, issues);
  requireNonEmptyString(source.base_path, `${sourcePath}.base_path`, issues);
}

function isMergeValue(value: unknown): boolean {
  if (typeof value === "string") {
    return value.trim().length > 0;
  }

  if (isRecord(value)) {
    return true;
  }

  return Array.isArray(value) && value.length > 0 && value.every((item) => typeof item === "string" || isRecord(item));
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function formatIssues(filePath: string, issues: ValidationIssue[]): string {
  const formattedIssues = issues.map((issue) => `- ${issue.path}: ${issue.message}`).join("\n");
  return `${filePath} failed authoring schema validation:\n${formattedIssues}`;
}
