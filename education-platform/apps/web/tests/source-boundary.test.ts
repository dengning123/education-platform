import { readdir, readFile } from "node:fs/promises";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { describe, expect, it } from "vitest";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const sourceRoot = join(root, "src");

async function sourceFiles(directory: string): Promise<string[]> {
  const entries = await readdir(directory, { withFileTypes: true });
  const nested = await Promise.all(entries.map(async (entry) => {
    const path = join(directory, entry.name);
    return entry.isDirectory() ? sourceFiles(path) : [path];
  }));
  return nested.flat().filter((path) => /\.(?:ts|tsx)$/.test(path) && !path.endsWith(".test.ts"));
}

describe("frontend source boundary", () => {
  it("references only the two browser-safe environment variables", async () => {
    const files = await sourceFiles(sourceRoot);
    const environmentNames = new Set<string>();

    for (const file of files) {
      const content = await readFile(file, "utf8");
      for (const match of content.matchAll(/process\.env\.([A-Z0-9_]+)/g)) {
        environmentNames.add(match[1]);
      }
    }

    expect([...environmentNames].sort()).toEqual([
      "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY",
      "NEXT_PUBLIC_SUPABASE_URL",
    ]);
  });

  it("contains no product-data or Edge Function request path in the 1A source", async () => {
    const files = await sourceFiles(sourceRoot);
    for (const file of files) {
      const content = await readFile(file, "utf8");
      expect(content, relative(root, file)).not.toMatch(/\/(?:rest|functions)\/v1\//);
      expect(content, relative(root, file)).not.toMatch(/\.from\s*\(/);
    }
  });

  it("does not add a frontend API route or backend credential adapter", async () => {
    const files = (await sourceFiles(sourceRoot)).map((file) => relative(root, file));
    expect(files.some((file) => file.startsWith("src/app/api/"))).toBe(false);
    expect(files.some((file) => /service-role|management-token|database-password/i.test(file))).toBe(false);
  });
});
