import { spawnSync } from "node:child_process";

import { defineConfig, devices } from "@playwright/test";

function localStatus() {
  const result = spawnSync(process.env.SUPABASE_BIN ?? "supabase", ["status", "--output", "json"], { encoding: "utf8" });
  if (result.status !== 0) throw new Error("Local Supabase status is unavailable");
  const start = result.stdout.indexOf("{");
  if (start < 0) throw new Error("Local Supabase status did not return JSON");
  return JSON.parse(result.stdout.slice(start)) as Record<string, string>;
}

const status = localStatus();
const apiUrl = new URL(status.API_URL);
if (!["127.0.0.1", "localhost"].includes(apiUrl.hostname) || !status.ANON_KEY) {
  throw new Error("Real-local browser tests require the disposable local Supabase stack");
}

const appOrigin = "http://127.0.0.1:3200";
const node = JSON.stringify(process.execPath);

export default defineConfig({
  testDir: "./tests/real-local",
  fullyParallel: false,
  workers: 1,
  retries: 0,
  reporter: "line",
  timeout: 120_000,
  use: {
    ...devices["Desktop Chrome"],
    baseURL: appOrigin,
    trace: "retain-on-failure",
  },
  webServer: {
    command: `${node} tests/real-local/start-next.mjs`,
    url: appOrigin,
    reuseExistingServer: false,
    timeout: 180_000,
    env: {
      ...process.env,
      NEXT_PUBLIC_SUPABASE_URL: apiUrl.toString().replace(/\/$/, ""),
      NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: status.ANON_KEY,
      REAL_LOCAL_NEXT_PORT: "3200",
    },
  },
});
