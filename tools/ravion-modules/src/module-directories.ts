export const NON_MODULE_DIRECTORIES = new Set([
  "node_modules",
  "dist",
  "tools",
  "test",
  "partials",
  "charts",
  // Module Definitions workflow checks trusted tooling out here.
  "trusted-tools",
]);

export function isModuleDirectory(name: string): boolean {
  return !name.startsWith(".") && !NON_MODULE_DIRECTORIES.has(name);
}
