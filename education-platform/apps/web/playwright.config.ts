import { defineConfig, devices } from "@playwright/test";

const appOrigin = "http://127.0.0.1:3100";
const authOrigin = "http://127.0.0.1:54321";
const publicKey = "sb_publishable_phase4b1a_browser_test";
const serviceRoleSentinel = "phase4b1a-service-role-must-stay-server-only";
const managementSentinel = "phase4b1a-management-token-must-stay-server-only";
const node = JSON.stringify(process.execPath);

export default defineConfig({
  testDir: "./tests/browser",
  fullyParallel: false,
  workers: 1,
  retries: 0,
  reporter: "line",
  use: {
    ...devices["Desktop Chrome"],
    baseURL: appOrigin,
    trace: "retain-on-failure",
  },
  webServer: [
    {
      command: `${node} tests/fake-supabase-server.mjs`,
      url: `${authOrigin}/health`,
      reuseExistingServer: false,
      timeout: 30_000,
      env: {
        ...process.env,
        FAKE_SUPABASE_PUBLIC_KEY: publicKey,
        FAKE_SUPABASE_ALLOWED_ORIGIN: appOrigin,
      },
    },
    {
      command: `${node} node_modules/next/dist/bin/next dev --hostname 127.0.0.1 --port 3100`,
      url: appOrigin,
      reuseExistingServer: false,
      timeout: 60_000,
      env: {
        ...process.env,
        NEXT_PUBLIC_SUPABASE_URL: authOrigin,
        NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: publicKey,
        SUPABASE_SERVICE_ROLE_KEY: serviceRoleSentinel,
        SUPABASE_ACCESS_TOKEN: managementSentinel,
      },
    },
  ],
  metadata: {
    serviceRoleSentinel,
    managementSentinel,
  },
});
