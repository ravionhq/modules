import { readdir, readFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import YAML from "yaml";
import { parseAuthoringDefinitionFile, type AuthoringDefinition } from "./authoring-schema.js";
import { validateUniqueDefinitionTypes } from "./guardrails.js";

export interface CompiledDefinition {
  filePath: string;
  published: boolean;
  global?: boolean;
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

const DEPLOY_REEXECUTES_STACK_TERRAFORM_VARIABLES = "$deploy_reexecutes_stack_terraform_variables";
const DIRECTIVE_KEYS = new Set(["$include", "$merge", "$template", DEPLOY_REEXECUTES_STACK_TERRAFORM_VARIABLES]);
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
  "monitoring",
  "networking",
  "security",
  "stack",
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

  const deployReexecutionVariables = consumeDeployReexecutionDirective(module, absoluteFilePath);
  rejectLeakedCompilerSyntax(module, absoluteFilePath, "module");
  deriveAppliedBy(module, absoluteFilePath, deployReexecutionVariables);

  return {
    filePath: absoluteFilePath,
    published: definition.published,
    global: definition.global,
    type: definition.definition.type,
    name: definition.definition.name,
    description: definition.definition.description,
    version: definition.release.version,
    releaseDescription: definition.release.description,
    module,
  };
}

const APPLY_ACTIONS = ["stack", "build", "deploy"] as const;
type ApplyAction = (typeof APPLY_ACTIONS)[number];

interface InputAnalysis {
  input: Record<string, unknown>;
  nestedKind?: "item_inputs" | "mapped_inputs";
  direct: Set<ApplyAction>;
  elementDirect: Set<ApplyAction>;
  children: InputAnalysis[];
  derived: Set<ApplyAction>;
}

export function deriveAppliedBy(
  module: Record<string, unknown>,
  filePath = "<module>",
  deployReexecutionVariables = consumeDeployReexecutionDirective(module, filePath),
): void {
  const inputs = module.inputs;
  if (!Array.isArray(inputs)) {
    return;
  }

  const analyses = inputs
    .filter((input): input is Record<string, unknown> => isRecord(input) && input.type !== "section")
    .map((input) => createInputAnalysis(input));

  const ambiguousNestedIds = new Set<string>();
  for (const action of APPLY_ACTIONS) {
    collectInputReferences(module[action], action, analyses, ambiguousNestedIds);
  }
  collectDeployReexecutionReferences(module, deployReexecutionVariables, analyses, filePath);

  for (const analysis of analyses) {
    resolveInputAnalysis(analysis, new Set());
    normalizeInputAnalysis(analysis);
    stampInputAnalysis(analysis, filePath);
  }
}

function consumeDeployReexecutionDirective(module: Record<string, unknown>, filePath: string): string[] {
  const deploy = module.deploy;
  if (!isRecord(deploy) || !(DEPLOY_REEXECUTES_STACK_TERRAFORM_VARIABLES in deploy)) {
    return [];
  }

  const value = deploy[DEPLOY_REEXECUTES_STACK_TERRAFORM_VARIABLES];
  delete deploy[DEPLOY_REEXECUTES_STACK_TERRAFORM_VARIABLES];
  if (
    !Array.isArray(value) ||
    value.length === 0 ||
    value.some((variable): variable is string => typeof variable !== "string" || variable.trim().length === 0)
  ) {
    throw new CompileError(
      `${filePath} module.deploy.${DEPLOY_REEXECUTES_STACK_TERRAFORM_VARIABLES}: expected a non-empty array of Terraform variable names.`,
    );
  }

  const variables = value as string[];
  if (new Set(variables).size !== variables.length) {
    throw new CompileError(
      `${filePath} module.deploy.${DEPLOY_REEXECUTES_STACK_TERRAFORM_VARIABLES}: variable names must be unique.`,
    );
  }
  return variables;
}

function collectDeployReexecutionReferences(
  module: Record<string, unknown>,
  variables: string[],
  analyses: InputAnalysis[],
  filePath: string,
): void {
  if (variables.length === 0) {
    return;
  }

  const terraformVariables = findTerraformVariableMaps(module.stack);
  const availableVariables = new Set(terraformVariables.flatMap((map) => Object.keys(map)));
  const missingVariables = variables.filter((variable) => !availableVariables.has(variable));
  if (missingVariables.length > 0) {
    throw new CompileError(
      `${filePath} module.deploy.${DEPLOY_REEXECUTES_STACK_TERRAFORM_VARIABLES}: Terraform variable(s) not found in module.stack: ${missingVariables.join(", ")}.`,
    );
  }

  for (const variable of variables) {
    const values = terraformVariables.flatMap((map) => (variable in map ? [map[variable]] : []));
    let feedsInput = false;
    for (const value of values) {
      feedsInput ||= collectInputReferences(value, "deploy", analyses, new Set());
    }
    if (!feedsInput) {
      throw new CompileError(
        `${filePath} module.deploy.${DEPLOY_REEXECUTES_STACK_TERRAFORM_VARIABLES}: Terraform variable ${variable} does not reference a module input.`,
      );
    }
  }
}

function findTerraformVariableMaps(value: unknown): Record<string, unknown>[] {
  if (Array.isArray(value)) {
    return value.flatMap((child) => findTerraformVariableMaps(child));
  }
  if (!isRecord(value)) {
    return [];
  }

  const maps = Object.entries(value).flatMap(([key, child]) =>
    key === "terraform_variables" && isRecord(child) ? [child] : findTerraformVariableMaps(child),
  );
  return maps;
}

function createInputAnalysis(input: Record<string, unknown>, nestedKind?: InputAnalysis["nestedKind"]): InputAnalysis {
  const children = [];
  for (const key of ["item_inputs", "mapped_inputs"] as const) {
    const nested = input[key];
    if (Array.isArray(nested)) {
      children.push(
        ...nested
          .filter((child): child is Record<string, unknown> => isRecord(child))
          .map((child) => createInputAnalysis(child, key)),
      );
    }
  }
  return { input, nestedKind, direct: new Set(), elementDirect: new Set(), children, derived: new Set() };
}

function collectInputReferences(
  value: unknown,
  action: ApplyAction,
  analyses: InputAnalysis[],
  ambiguousNestedIds: Set<string>,
): boolean {
  if (Array.isArray(value)) {
    let matchedReference = false;
    value.forEach((item) => {
      matchedReference = collectInputReferences(item, action, analyses, ambiguousNestedIds) || matchedReference;
    });
    return matchedReference;
  }
  if (typeof value === "string") {
    const referencePattern = /\bmodule\.input\.([A-Za-z0-9_-]+(?:(?:\.[A-Za-z0-9_-]+)|(?:\[[^\]]+\]))*)/g;
    const references = [...value.matchAll(referencePattern)]
      .map((match) => ({
        end: (match.index ?? 0) + match[0].length,
        path: match[1],
        start: match.index ?? 0,
      }))
      .filter((reference): reference is { end: number; path: string; start: number } => Boolean(reference.path))
      .map((reference) => ({ ...reference, parts: parseInputReferencePath(reference.path) }));
    const elementReferences = [...value.matchAll(/#\.([A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*)/g)]
      .map((match) => ({
        path: match[1],
        start: match.index ?? 0,
      }))
      .filter((reference): reference is { path: string; start: number } => Boolean(reference.path))
      .map((reference) => ({ ...reference, parts: reference.path.split(".") }));
    const mapReferences = findMapReferences(value);
    let matchedReference = false;

    for (const reference of references) {
      const hasElementAccess = reference.parts.some((part) => part.startsWith("["));
      if (hasElementAccess) {
      const matched = markInputReference(reference.parts, action, analyses, ambiguousNestedIds);
        if (matched) {
          matchedReference = true;
        }
        continue;
      }
      const mapReference = mapReferences.find(
        (candidate) =>
          candidate.argumentStart <= reference.start &&
          reference.end <= candidate.argumentEnd &&
          candidate.elementReferences.some(
            (elementReference) =>
              candidate.start <= elementReference.start && elementReference.start < candidate.end,
          ),
      );
      const matched = markInputReference(reference.parts, action, analyses, ambiguousNestedIds, !mapReference);
      if (matched) {
        matchedReference = true;
      }
    }

    for (const elementReference of elementReferences) {
      const containingMaps = mapReferences
        .filter((candidate) => candidate.start <= elementReference.start && elementReference.start < candidate.end)
        .sort((left, right) => left.end - left.start - (right.end - right.start));
      const mapReference = containingMaps[0];
      if (!mapReference?.collectionPath) {
        const candidates = analyses.filter((analysis) => analysis.children.length > 0);
        warnAmbiguousElementReference(elementReference.path, ambiguousNestedIds);
        for (const analysis of candidates) {
          matchedReference =
            markNestedInputReference(analysis, elementReference.parts, action, ambiguousNestedIds) || matchedReference;
        }
        continue;
      }
      const [id, ...nestedPath] = mapReference.collectionPath;
      const analysis = analyses.find((candidate) => candidate.input.id === id);
      if (!analysis) {
        warnAmbiguousElementReference(elementReference.path, ambiguousNestedIds);
        for (const candidate of analyses.filter((candidate) => candidate.children.length > 0)) {
          matchedReference =
            markNestedInputReference(candidate, elementReference.parts, action, ambiguousNestedIds) || matchedReference;
        }
        continue;
      }
      matchedReference =
        markNestedInputReference(analysis, nestedPath.concat(elementReference.parts), action, ambiguousNestedIds) ||
        matchedReference;
    }
    return matchedReference;
  }
  if (!isRecord(value)) {
    return false;
  }
  let matchedReference = false;
  Object.values(value).forEach((child) => {
    matchedReference = collectInputReferences(child, action, analyses, ambiguousNestedIds) || matchedReference;
  });
  return matchedReference;
}

function markInputReference(
  path: string[],
  action: ApplyAction,
  analyses: InputAnalysis[],
  ambiguousNestedIds: Set<string>,
  inheritToChildren = true,
): boolean {
  const [id, ...nestedPath] = path;
  if (!id) {
    return false;
  }
  const analysis = analyses.find((candidate) => candidate.input.id === id);
  if (analysis) {
    return markNestedInputReference(analysis, nestedPath, action, ambiguousNestedIds, inheritToChildren);
  }
  const nestedMatches = findMappedInputAnalyses(id, analyses);
  if (nestedMatches.length > 1) {
    if (!ambiguousNestedIds.has(id)) {
      ambiguousNestedIds.add(id);
      console.warn(`Ambiguous mapped input reference: ${id}`);
    }
    return false;
  }
  const nestedAnalysis = nestedMatches[0];
  if (nestedAnalysis) {
    return markNestedInputReference(nestedAnalysis, nestedPath, action, ambiguousNestedIds, inheritToChildren);
  }
  return false;
}

function findMappedInputAnalyses(id: string, analyses: InputAnalysis[]): InputAnalysis[] {
  const matches: InputAnalysis[] = [];
  for (const analysis of analyses) {
    if (analysis.nestedKind === "mapped_inputs" && analysis.input.id === id) {
      matches.push(analysis);
    }
    matches.push(...findMappedInputAnalyses(id, analysis.children));
  }
  return matches;
}

function markNestedInputReference(
  analysis: InputAnalysis,
  path: string[],
  action: ApplyAction,
  ambiguousNestedIds: Set<string>,
  inheritToChildren = true,
): boolean {
  if (path.length === 0) {
    (inheritToChildren ? analysis.direct : analysis.elementDirect).add(action);
    return true;
  }
  const [id, ...nestedPath] = path;
  if (id?.startsWith("[")) {
    return markNestedInputReference(analysis, nestedPath, action, ambiguousNestedIds, inheritToChildren);
  }
  const child = analysis.children.find((candidate) => candidate.input.id === id);
  if (child) {
    return markNestedInputReference(child, nestedPath, action, ambiguousNestedIds, inheritToChildren);
  }
  const mappedMatches = findMappedInputAnalyses(id, analysis.children);
  if (mappedMatches.length > 1) {
    if (!ambiguousNestedIds.has(id)) {
      ambiguousNestedIds.add(id);
      console.warn(`Ambiguous mapped input reference: ${id}`);
    }
    return false;
  }
  const mappedChild = mappedMatches[0];
  if (mappedChild) {
    return markNestedInputReference(mappedChild, nestedPath, action, ambiguousNestedIds, inheritToChildren);
  } else {
    (inheritToChildren ? analysis.direct : analysis.elementDirect).add(action);
    return true;
  }
}

function parseInputReferencePath(path: string): string[] {
  return path.match(/[A-Za-z0-9_-]+|\[[^\]]+\]/g) ?? [];
}

interface MapReference {
  argumentEnd: number;
  argumentStart: number;
  collectionPath?: string[];
  elementReferences: { start: number }[];
  end: number;
  start: number;
}

function findMapReferences(value: string): MapReference[] {
  const references: MapReference[] = [];
  for (const match of value.matchAll(/\bmap\s*\(/g)) {
    const start = match.index ?? 0;
    const open = start + match[0].length - 1;
    const end = findMatchingParenthesis(value, open);
    if (end === undefined) {
      continue;
    }
    const comma = findTopLevelComma(value, open, end);
    if (comma === undefined) {
      continue;
    }
    const argumentStart = open + 1;
    const argument = value.slice(argumentStart, comma).trim();
    const collectionMatch = argument.match(/^module\.input\.([A-Za-z0-9_-]+(?:(?:\.[A-Za-z0-9_-]+)|(?:\[[^\]]+\]))*)$/);
    const elementReferences = [...value.slice(comma + 1, end).matchAll(/#\.([A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*)/g)].map(
      (elementReference) => ({ start: comma + 1 + (elementReference.index ?? 0) }),
    );
    references.push({
      argumentEnd: comma,
      argumentStart,
      collectionPath: collectionMatch?.[1] ? parseInputReferencePath(collectionMatch[1]) : undefined,
      elementReferences,
      end,
      start,
    });
  }
  return references;
}

function findMatchingParenthesis(value: string, open: number): number | undefined {
  let depth = 0;
  let quote: string | undefined;
  for (let index = open; index < value.length; index += 1) {
    const character = value[index];
    if (quote) {
      if (character === "\\" && index + 1 < value.length) {
        index += 1;
      } else if (character === quote) {
        quote = undefined;
      }
      continue;
    }
    if (character === '"' || character === "'") {
      quote = character;
    } else if (character === "(") {
      depth += 1;
    } else if (character === ")" && --depth === 0) {
      return index;
    }
  }
  return undefined;
}

function findTopLevelComma(value: string, open: number, end: number): number | undefined {
  let depth = 0;
  let quote: string | undefined;
  for (let index = open + 1; index < end; index += 1) {
    const character = value[index];
    if (quote) {
      if (character === "\\" && index + 1 < end) {
        index += 1;
      } else if (character === quote) {
        quote = undefined;
      }
      continue;
    }
    if (character === '"' || character === "'") {
      quote = character;
    } else if (character === "(") {
      depth += 1;
    } else if (character === ")") {
      depth -= 1;
    } else if (character === "," && depth === 0) {
      return index;
    }
  }
  return undefined;
}

function warnAmbiguousElementReference(path: string, ambiguousNestedIds: Set<string>): void {
  const warningKey = `element:${path}`;
  if (!ambiguousNestedIds.has(warningKey)) {
    ambiguousNestedIds.add(warningKey);
    console.warn(`Ambiguous collection element reference: ${path}`);
  }
}

function resolveInputAnalysis(analysis: InputAnalysis, inherited: Set<ApplyAction>): Set<ApplyAction> {
  const actions = new Set([...analysis.direct, ...analysis.elementDirect]);
  const childInheritance = analysis.direct.size > 0 ? analysis.direct : inherited;
  for (const child of analysis.children) {
    const childActions = resolveInputAnalysis(child, childInheritance);
    for (const action of childActions) {
      actions.add(action);
    }
  }
  if (actions.size === 0) {
    for (const action of inherited) {
      actions.add(action);
    }
  }
  analysis.derived = actions;
  return actions;
}

function normalizeInputAnalysis(analysis: InputAnalysis): void {
  if (analysis.derived.has("build")) {
    analysis.derived.add("deploy");
  }
  analysis.children.forEach((child) => normalizeInputAnalysis(child));
}

function stampInputAnalysis(analysis: InputAnalysis, filePath: string): void {
  const derived = APPLY_ACTIONS.filter((action) => analysis.derived.has(action));
  if ("applies_on" in analysis.input) {
    throw new CompileError(
      `${filePath}: input ${String(analysis.input.id)} uses the old applies_on field; use applied_by instead.`,
    );
  }
  const authored = analysis.input.applied_by;
  if (Array.isArray(authored)) {
    console.warn(
      `${filePath}: input ${String(analysis.input.id)} authors applied_by; prefer compiler derivation. Correct the module wiring instead, or use module.deploy.$deploy_reexecutes_stack_terraform_variables for stack-rendered deploy artifacts. Hand-authored applied_by should be a justified last resort.`,
    );
    const missing = derived.filter((action) => !authored.includes(action));
    if (missing.length > 0) {
      console.warn(
        `${filePath}: input ${String(analysis.input.id)} authored applied_by is missing statically derived action(s): ${missing.join(", ")}`,
      );
    }
  } else {
    analysis.input.applied_by = derived;
  }
  analysis.children.forEach((child) => stampInputAnalysis(child, filePath));
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
