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

  it("contains no direct browser PostgREST, table, or Edge Function request path", async () => {
    const files = await sourceFiles(sourceRoot);
    for (const file of files) {
      const content = await readFile(file, "utf8");
      if (/\/(?:rest|functions)\/v1\//.test(content)) {
        expect(relative(root, file)).toBe("src/lib/evaluation/service.ts");
        expect(content).toMatch(/^import "server-only";/);
      }
      expect(content, relative(root, file)).not.toMatch(/\.from\s*\(/);
    }
  });

  it("keeps taxonomy projection and bounded options behind the existing session-scoped Profile route", async () => {
    const service = await readFile(join(root, "src/lib/profile/service.ts"), "utf8");
    const boundary = await readFile(join(root, "src/lib/profile/http-boundary.ts"), "utf8");
    expect(service).toContain('this.rpc("get_profile_taxonomy_projection_v022"');
    expect(service).toContain('this.rpc("get_profile_taxonomy_options_v023"');
    expect(service).toContain("parseProfileTaxonomyProjection");
    expect(service).toContain("parseProfileTaxonomyOptions");
    expect(boundary).toContain('"taxonomy"');
    expect(boundary).toContain("parseTaxonomyRequest");
    expect(service).not.toMatch(/service.?role|management.?token|database.?password/i);
  });

  it("adds only the approved Profile, Intent, and evaluation capability routes", async () => {
    const files = (await sourceFiles(sourceRoot)).map((file) => relative(root, file));
    expect(files.filter((file) => file.startsWith("src/app/api/")).sort()).toEqual([
      "src/app/api/evaluation/[capability]/route.ts",
      "src/app/api/intent/[capability]/route.ts",
      "src/app/api/profile/[capability]/route.ts",
    ]);
    expect(files.some((file) => /service-role|management-token|database-password/i.test(file))).toBe(false);
  });

  it("keeps M027 Intent behind the session service and delegates authoritative Fit assembly to the Edge", async () => {
    const intent = await readFile(join(root, "src/lib/intent/service.ts"), "utf8");
    const evaluation = await readFile(join(root, "src/lib/evaluation/service.ts"), "utf8");
    expect(intent).toMatch(/^import "server-only";/);
    expect(intent).toContain('this.rpc("mutate_fit_intent_draft_v027"');
    expect(intent).toContain('this.rpc("freeze_fit_intent_draft_v027"');
    expect(evaluation).toContain('schemaVersion: "FIT_PRODUCT_EVALUATION_REQUEST_V027"');
    expect(evaluation).not.toContain('this.supabase.rpc("get_fit_evaluation_assembly_v027"');
    expect(intent).not.toMatch(/service.?role|management.?token|database.?password/i);
    expect(evaluation).not.toMatch(/service.?role|management.?token|database.?password/i);
  });

  it("runs the real-local Fit path with the exact disposable Edge Runtime and preserves JWT verification", async () => {
    const harness = await readFile(join(root, "tests/real-local/start-next.mjs"), "utf8");
    expect(harness).toContain('["functions", "serve", "--env-file", edgeConfigurationFile, "--log-level", "info"]');
    expect(harness).toContain('"supabase_edge_runtime_capibara-education-platform"');
    expect(harness).toContain('["inspect", "--format", "{{.State.Status}}", edgeRuntimeContainer]');
    expect(harness).toContain('functions.kill("SIGTERM")');
    expect(harness).toContain('"FIT_EDGE_ALLOWED_ORIGINS=none"');
    expect(harness).toContain('"FIT_EDGE_SEMANTIC_RELEASE=fit-v0.1"');
    expect(harness).toContain('"FIT_EDGE_DEPLOYED_BUILD=phase4b-m027-real-local"');
    expect(harness).toContain("mode: 0o600");
    expect(harness).toContain("rmSync(edgeConfigurationDirectory, { recursive: true, force: true })");
    expect(harness).not.toContain("--no-verify-jwt");
  });

  it("keeps test adapters and production bypasses out of application source", async () => {
    const files = await sourceFiles(sourceRoot);
    for (const file of files) {
      const content = await readFile(file, "utf8");
      expect(content, relative(root, file)).not.toMatch(/FAKE_SUPABASE|__test__|fixture-bypass/i);
    }
  });
});
