import { spawn, spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const next = new URL("../../node_modules/next/dist/bin/next", import.meta.url).pathname;
const webRoot = new URL("../../", import.meta.url);
const repositoryRoot = new URL("../../../", import.meta.url);
const build = spawnSync(process.execPath, [next, "build"], { cwd: webRoot, env: process.env, stdio: "inherit" });
if (build.status !== 0) process.exit(build.status ?? 1);

const supabase = process.env.SUPABASE_BIN ?? "supabase";
const docker = process.env.DOCKER_BIN ?? "docker";
const edgeRuntimeContainer = "supabase_edge_runtime_capibara-education-platform";
const edgeConfigurationDirectory = mkdtempSync(join(tmpdir(), "education-platform-edge-"));
const edgeConfigurationFile = join(edgeConfigurationDirectory, "boundary.env");
writeFileSync(edgeConfigurationFile, [
  "FIT_EDGE_ALLOWED_ORIGINS=none",
  "FIT_EDGE_SEMANTIC_RELEASE=fit-v0.1",
  "FIT_EDGE_DEPLOYED_BUILD=phase4b-m027-real-local",
  "",
].join("\n"), { encoding: "utf8", mode: 0o600, flag: "wx" });
let edgeConfigurationRemoved = false;
function removeEdgeConfiguration() {
  if (edgeConfigurationRemoved) return;
  edgeConfigurationRemoved = true;
  rmSync(edgeConfigurationDirectory, { recursive: true, force: true });
}
process.once("exit", removeEdgeConfiguration);

const functions = spawn(supabase, ["functions", "serve", "--env-file", edgeConfigurationFile, "--log-level", "info"], {
  cwd: repositoryRoot,
  env: process.env,
  stdio: "inherit",
});

const edgeDeadline = Date.now() + 60_000;
let edgeReady = false;
while (Date.now() < edgeDeadline) {
  if (functions.exitCode !== null) process.exit(functions.exitCode || 1);
  const inspected = spawnSync(docker, ["inspect", "--format", "{{.State.Status}}", edgeRuntimeContainer], {
    cwd: repositoryRoot,
    env: process.env,
    encoding: "utf8",
  });
  if (inspected.status === 0 && inspected.stdout.trim() === "running") {
    edgeReady = true;
    break;
  }
  await new Promise((resolve) => setTimeout(resolve, 250));
}
if (!edgeReady) {
  functions.kill("SIGTERM");
  process.exit(74);
}

const server = spawn(process.execPath, [next, "start", "--hostname", "127.0.0.1", "--port", process.env.REAL_LOCAL_NEXT_PORT ?? "3200"], {
  cwd: webRoot,
  env: process.env,
  stdio: "inherit",
});

let stopping = false;
let serverExit = null;
let functionsExit = null;

function finishWhenStopped() {
  if (serverExit === null || functionsExit === null) return;
  const failed = [serverExit.code, functionsExit.code].find((code) => code !== 0);
  process.exit(failed ?? 0);
}

function stop(signal = "SIGTERM") {
  if (stopping) return;
  stopping = true;
  if (server.exitCode === null) server.kill(signal);
  if (functions.exitCode === null) functions.kill(signal);
  setTimeout(() => process.exit(1), 10_000).unref();
}

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => stop(signal));
}
server.once("exit", (code, signal) => {
  serverExit = { code: code ?? (signal ? 1 : 0) };
  if (!stopping) stop();
  finishWhenStopped();
});
functions.once("exit", (code, signal) => {
  removeEdgeConfiguration();
  functionsExit = { code: code ?? (signal ? 1 : 0) };
  if (!stopping) stop();
  finishWhenStopped();
});
