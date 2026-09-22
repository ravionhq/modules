import { readFile, writeFile } from "node:fs/promises";
import { dirname, join, relative, resolve, sep } from "node:path";
import { compileAllDefinitions, type CompiledDefinition } from "./compiler.js";

export const README_TABLE_BEGIN_MARKER = "<!-- BEGIN GENERATED: module-definitions -->";
export const README_TABLE_END_MARKER = "<!-- END GENERATED: module-definitions -->";

export class ReadmeSyncError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ReadmeSyncError";
  }
}

export interface ReadmeSyncResult {
  readmePath: string;
  changed: boolean;
  content: string;
}

export function renderModuleDefinitionsTable(compiledDefinitions: CompiledDefinition[], rootPath = process.cwd()): string {
  const rows = compiledDefinitions
    .filter((definition) => definition.published)
    .map((definition) => {
      const modulePath = relative(resolve(rootPath), dirname(definition.filePath)).split(sep).join("/");
      return {
        type: definition.type,
        name: definition.name,
        version: definition.version,
        modulePath,
      };
    })
    .sort((left, right) => left.type.localeCompare(right.type));

  const lines = [
    "| Definition | Name | Version | Module path |",
    "| ---------- | ---- | ------- | ----------- |",
    ...rows.map((row) => `| \`${row.type}\` | ${row.name} | v${row.version} | \`${row.modulePath}/\` |`),
  ];
  return lines.join("\n");
}

export function updateReadmeContent(readmeContent: string, table: string): string {
  const beginIndex = readmeContent.indexOf(README_TABLE_BEGIN_MARKER);
  const endIndex = readmeContent.indexOf(README_TABLE_END_MARKER);
  if (beginIndex < 0 || endIndex < 0 || endIndex < beginIndex) {
    throw new ReadmeSyncError(`README is missing the generated module definitions markers ${README_TABLE_BEGIN_MARKER} and ${README_TABLE_END_MARKER}.`);
  }

  const before = readmeContent.slice(0, beginIndex + README_TABLE_BEGIN_MARKER.length);
  const after = readmeContent.slice(endIndex);
  return `${before}\n\n${table}\n\n${after}`;
}

export async function syncReadme(options: { rootPath?: string; write?: boolean } = {}): Promise<ReadmeSyncResult> {
  const rootPath = resolve(options.rootPath ?? process.cwd());
  const readmePath = join(rootPath, "README.md");
  const readmeContent = await readFile(readmePath, "utf8");
  const compiled = await compileAllDefinitions(rootPath);
  const content = updateReadmeContent(readmeContent, renderModuleDefinitionsTable(compiled, rootPath));
  const changed = content !== readmeContent;

  if (changed && options.write) {
    await writeFile(readmePath, content);
  }

  return { readmePath, changed, content };
}
