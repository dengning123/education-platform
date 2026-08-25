#!/usr/bin/env node

import { createHash } from "node:crypto";
import { access, readFile, realpath, statfs } from "node:fs/promises";
import { spawn } from "node:child_process";
import { dirname, resolve, sep } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import {
  COMMAND_CATALOG,
  FROZEN_AUDIT_PATHS,
  FROZEN_FIT_RUNTIME_SHA256,
  GATE_REQUIRED_ORDERS,
  HEAVY_MIN_FREE_BYTES,
  LIGHT_MIN_FREE_BYTES,
  LOCAL_AUTH_CONTAINER,
  LOCAL_AUTH_DB_CONTAINER,
  MANIFEST_SCHEMA_VERSION,
} from "./phase4-layered-gates.catalog.mjs";

const here = dirname(fileURLToPath(import.meta.url));
export const REPOSITORY_ROOT = resolve(here, "..");
export const DEFAULT_MANIFEST_PATH = resolve(here, "phase4-layered-gates.manifest.json");
const GATE_NAMES = Object.freeze(["FAST", "RELEVANT", "BASELINE", "RELEASE"]);
const SAFE_DOCKER_PREFLIGHT_ACTIONS = new Set(["version", "info", "ps", "inspect", "logs"]);
const CORRUPTION_PATTERN =
  /read-only file system|input\/output error|\bi\/o error\b|wal[^\n]{0,80}fsync|potential data loss|ext4[^\n]{0,80}error/i;
const PROJECT_REF_PATTERN = /^[a-z]{20}$/;
const SAFE_TEXT_PATTERN = /^[\x20-\x7e]{1,800}$/;
const COMMAND_ID_PATTERN = /^[a-z0-9]+(?:[.-][a-z0-9]+)*$/;
const OUTPUT_LIMIT = 1024 * 1024;

export class LayeredGateError extends Error {
  constructor(code) {
    super(code);
    this.name = "LayeredGateError";
    this.code = code;
  }
}

function fail(code) {
  throw new LayeredGateError(code);
}

function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function exactKeys(value, expected, code) {
  if (!isRecord(value)) fail(code);
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  if (JSON.stringify(actual) !== JSON.stringify(wanted)) fail(code);
}

function safeText(value, code) {
  if (typeof value !== "string" || !SAFE_TEXT_PATTERN.test(value)) fail(code);
  return value;
}

function sameOrder(actual, expected) {
  return JSON.stringify(actual) === JSON.stringify(expected);
}

export async function loadManifest(path = DEFAULT_MANIFEST_PATH) {
  try {
    return JSON.parse(await readFile(path, "utf8"));
  } catch {
    fail("MANIFEST_UNREADABLE_OR_INVALID_JSON");
  }
}

export function validateManifest(manifest, catalog = COMMAND_CATALOG) {
  exactKeys(manifest, ["schemaVersion", "policy", "gates"], "MANIFEST_TOP_LEVEL_CLOSED");
  if (manifest.schemaVersion !== MANIFEST_SCHEMA_VERSION) fail("MANIFEST_SCHEMA_VERSION_REJECTED");

  exactKeys(manifest.policy, [
    "failFast",
    "shellExecution",
    "baselineChangedPathSkipping",
    "releaseChangedPathSkipping",
    "diskThresholdBytes",
  ], "MANIFEST_POLICY_CLOSED");
  exactKeys(manifest.policy.diskThresholdBytes, ["light", "heavy"], "MANIFEST_DISK_POLICY_CLOSED");
  if (manifest.policy.failFast !== true || manifest.policy.shellExecution !== false ||
      manifest.policy.baselineChangedPathSkipping !== false ||
      manifest.policy.releaseChangedPathSkipping !== false) {
    fail("MANIFEST_FAIL_CLOSED_POLICY_WEAKENED");
  }
  if (manifest.policy.diskThresholdBytes.light !== LIGHT_MIN_FREE_BYTES ||
      manifest.policy.diskThresholdBytes.heavy !== HEAVY_MIN_FREE_BYTES) {
    fail("MANIFEST_DISK_THRESHOLD_WEAKENED");
  }

  exactKeys(manifest.gates, GATE_NAMES, "MANIFEST_GATE_SET_CLOSED");
  for (const gateName of GATE_NAMES) {
    const gate = manifest.gates[gateName];
    const keys = gateName === "RELEASE"
      ? ["description", "classification", "extends", "prerequisites", "commands"]
      : ["description", "classification", "prerequisites", "commands"];
    exactKeys(gate, keys, `MANIFEST_${gateName}_CLOSED`);
    safeText(gate.description, `MANIFEST_${gateName}_DESCRIPTION_INVALID`);
    if (gate.classification !== (gateName === "FAST" ? "light" : "heavy")) {
      fail(`MANIFEST_${gateName}_CLASSIFICATION_INVALID`);
    }
    if (gateName === "RELEASE" && gate.extends !== "BASELINE") {
      fail("MANIFEST_RELEASE_NOT_BASELINE_SUPERSET");
    }
    if (!Array.isArray(gate.prerequisites) || gate.prerequisites.length === 0) {
      fail(`MANIFEST_${gateName}_PREREQUISITES_INVALID`);
    }
    for (const prerequisite of gate.prerequisites) {
      safeText(prerequisite, `MANIFEST_${gateName}_PREREQUISITE_INVALID`);
    }
    if (!Array.isArray(gate.commands) || gate.commands.length === 0) {
      fail(`MANIFEST_${gateName}_COMMANDS_INVALID`);
    }
    const ids = [];
    for (const command of gate.commands) {
      exactKeys(command, ["id", "why"], `MANIFEST_${gateName}_COMMAND_ENTRY_CLOSED`);
      if (typeof command.id !== "string" || !COMMAND_ID_PATTERN.test(command.id)) {
        fail("MANIFEST_COMMAND_ID_INVALID");
      }
      if (!Object.hasOwn(catalog, command.id)) fail("MANIFEST_UNKNOWN_COMMAND");
      safeText(command.why, `MANIFEST_${gateName}_WHY_INVALID`);
      ids.push(command.id);
    }
    if (new Set(ids).size !== ids.length) fail(`MANIFEST_${gateName}_COMMAND_DUPLICATE`);
    if (!sameOrder(ids, GATE_REQUIRED_ORDERS[gateName])) {
      if (gateName === "BASELINE") fail("MANIFEST_BASELINE_RIGOR_WEAKENED");
      if (gateName === "RELEASE") fail("MANIFEST_RELEASE_RIGOR_WEAKENED");
      fail(`MANIFEST_${gateName}_ORDER_REJECTED`);
    }
  }

  const baseline = manifest.gates.BASELINE.commands.map(({ id }) => id);
  const release = resolveGate(manifest, "RELEASE", catalog).map(({ id }) => id);
  if (!sameOrder(release.slice(0, baseline.length), baseline) || release.length <= baseline.length) {
    fail("MANIFEST_RELEASE_NOT_STRICT_BASELINE_SUPERSET");
  }
  return manifest;
}

export function resolveGate(manifest, gateName, catalog = COMMAND_CATALOG) {
  if (!GATE_NAMES.includes(gateName)) fail("MANIFEST_UNKNOWN_GATE");
  const own = manifest.gates[gateName].commands;
  const commands = gateName === "RELEASE"
    ? [...manifest.gates.BASELINE.commands, ...own]
    : own;
  return commands.map((entry, index) => ({
    order: index + 1,
    id: entry.id,
    why: entry.why,
    spec: catalog[entry.id],
  }));
}

function safeRepositoryPath(relativePath) {
  if (typeof relativePath !== "string" || relativePath.length === 0) {
    fail("CATALOG_REFERENCE_INVALID");
  }
  const path = resolve(REPOSITORY_ROOT, relativePath);
  if (path !== REPOSITORY_ROOT && !path.startsWith(`${REPOSITORY_ROOT}${sep}`)) {
    fail("CATALOG_REFERENCE_OUTSIDE_REPOSITORY");
  }
  return path;
}

function catalogReferences(spec) {
  const references = [];
  if (spec.cwd) references.push(spec.cwd);
  if (Array.isArray(spec.files)) references.push(...spec.files);
  if (Array.isArray(spec.scripts)) references.push(...spec.scripts);
  if (spec.script) references.push(spec.script);
  if (spec.kind === "spawn") {
    for (const arg of spec.args ?? []) {
      if (/\.(?:mjs|js|ts|sql)$/.test(arg) && !arg.startsWith("--")) {
        references.push(resolve(REPOSITORY_ROOT, spec.cwd ?? ".", arg));
      }
    }
  }
  return references;
}

export async function validateCatalogReferences(catalog = COMMAND_CATALOG) {
  for (const [id, spec] of Object.entries(catalog)) {
    if (!COMMAND_ID_PATTERN.test(id) || !isRecord(spec) ||
        !["light", "heavy"].includes(spec.classification) ||
        typeof spec.kind !== "string" || typeof spec.display !== "string") {
      fail("CATALOG_ENTRY_INVALID");
    }
    safeText(spec.display, "CATALOG_DISPLAY_INVALID");
    if (Object.hasOwn(spec, "shell")) fail("CATALOG_SHELL_EXECUTION_FORBIDDEN");
    for (const reference of catalogReferences(spec)) {
      const path = safeRepositoryPath(reference);
      try {
        await access(path);
        const resolved = await realpath(path);
        if (resolved !== REPOSITORY_ROOT && !resolved.startsWith(`${REPOSITORY_ROOT}${sep}`)) {
          fail("CATALOG_REFERENCE_SYMLINK_ESCAPE");
        }
      } catch (error) {
        if (error instanceof LayeredGateError) throw error;
        fail("CATALOG_REFERENCE_MISSING");
      }
    }
  }
  for (const path of FROZEN_AUDIT_PATHS) {
    try {
      await access(safeRepositoryPath(path));
    } catch {
      fail("CATALOG_FROZEN_AUDIT_REFERENCE_MISSING");
    }
  }
  return true;
}

export function formatGatePlan(manifest, gateName, mode = "dry-run", catalog = COMMAND_CATALOG) {
  if (mode !== "dry-run" && mode !== "explain") fail("CLI_MODE_REJECTED");
  const gate = manifest.gates[gateName];
  if (!gate) fail("MANIFEST_UNKNOWN_GATE");
  const commands = resolveGate(manifest, gateName, catalog);
  const prerequisites = new Set(gate.prerequisites);
  if (gateName === "RELEASE") {
    for (const value of manifest.gates.BASELINE.prerequisites) prerequisites.add(value);
  }
  for (const { spec } of commands) {
    for (const value of spec.prerequisites ?? []) prerequisites.add(value);
  }
  const lines = [
    `MODE=${mode === "dry-run" ? "DRY_RUN" : "EXPLAIN"}`,
    `GATE=${gateName}`,
    `CLASSIFICATION=${gate.classification}`,
    `COMMAND_COUNT=${commands.length}`,
    "PREREQUISITES:",
    ...[...prerequisites].map((value, index) => `  ${index + 1}. ${value}`),
    "EXECUTION_ORDER:",
  ];
  for (const command of commands) {
    lines.push(
      `  ${command.order}. ${command.id} [${command.spec.classification}]`,
      `     command: ${command.spec.display}`,
      `     why: ${command.why}`,
    );
  }
  lines.push("EXECUTION=NONE");
  return `${lines.join("\n")}\n`;
}

function resolveTool(tool, environment = process.env) {
  const overrides = {
    docker: ["PHASE4_DOCKER_BIN", "DOCKER_BIN"],
    supabase: ["PHASE4_SUPABASE_BIN", "SUPABASE_BIN"],
    pnpm: ["PHASE4_PNPM_BIN"],
    npm: ["PHASE4_NPM_BIN"],
    git: ["PHASE4_GIT_BIN"],
  };
  if (tool === "node") return process.execPath;
  if (!Object.hasOwn(overrides, tool)) fail("CATALOG_TOOL_REJECTED");
  for (const name of overrides[tool]) {
    if (typeof environment[name] === "string" && environment[name].length > 0) {
      return environment[name];
    }
  }
  return tool;
}

function spawnResult(bin, args, options, capture) {
  return new Promise((resolveResult) => {
    let stdout = "";
    let stderr = "";
    let child;
    try {
      child = spawn(bin, args, {
        cwd: options.cwd,
        env: options.env,
        shell: false,
        stdio: capture ? ["ignore", "pipe", "pipe"] : "inherit",
      });
    } catch {
      resolveResult({ exitCode: 127, stdout: "", stderr: "" });
      return;
    }
    if (capture) {
      child.stdout.on("data", (chunk) => {
        if (stdout.length < OUTPUT_LIMIT) stdout += chunk.toString("utf8").slice(0, OUTPUT_LIMIT - stdout.length);
      });
      child.stderr.on("data", (chunk) => {
        if (stderr.length < OUTPUT_LIMIT) stderr += chunk.toString("utf8").slice(0, OUTPUT_LIMIT - stderr.length);
      });
    }
    child.once("error", () => resolveResult({ exitCode: 127, stdout: "", stderr: "" }));
    child.once("close", (code, signal) => {
      resolveResult({
        exitCode: Number.isInteger(code) ? code : signal ? 128 : 127,
        stdout,
        stderr,
      });
    });
  });
}

function spawnCapture(bin, args, options = {}) {
  return spawnResult(bin, args, options, true);
}

function spawnInherit(bin, args, options = {}) {
  return spawnResult(bin, args, options, false);
}

async function defaultFreeBytes() {
  const value = await statfs(REPOSITORY_ROOT);
  return Number(value.bavail) * Number(value.bsize);
}

async function defaultDockerProbe(args, environment = process.env) {
  return spawnCapture(resolveTool("docker", environment), args, {
    cwd: REPOSITORY_ROOT,
    env: environment,
  });
}

export async function runReadOnlyPreflight({
  diskClass,
  requireDocker,
  freeBytesProvider = defaultFreeBytes,
  dockerProbe = defaultDockerProbe,
  environment = process.env,
} = {}) {
  if (!(["light", "heavy"].includes(diskClass)) || typeof requireDocker !== "boolean") {
    fail("PREFLIGHT_CONFIGURATION_INVALID");
  }
  let freeBytes;
  try {
    freeBytes = await freeBytesProvider();
  } catch {
    return { exitCode: 72, code: "PREFLIGHT_DISK_UNREADABLE" };
  }
  const thresholdBytes = diskClass === "heavy" ? HEAVY_MIN_FREE_BYTES : LIGHT_MIN_FREE_BYTES;
  if (!Number.isSafeInteger(freeBytes) || freeBytes < 0) {
    return { exitCode: 72, code: "PREFLIGHT_DISK_VALUE_INVALID" };
  }
  if (freeBytes < thresholdBytes) {
    return { exitCode: 75, code: "PREFLIGHT_DISK_BELOW_THRESHOLD", freeBytes, thresholdBytes };
  }
  if (!requireDocker) {
    return {
      exitCode: 0,
      code: "PREFLIGHT_PASS",
      freeBytes,
      thresholdBytes,
      docker: "NOT_REQUIRED",
    };
  }

  const calls = [
    ["version", "--format", "{{.Server.Version}}"],
    ["info", "--format", "{{json .Warnings}}"],
    ["ps", "--filter", `name=${LOCAL_AUTH_DB_CONTAINER}`, "--format", "{{.Names}}|{{.Status}}"],
  ];
  const outputs = [];
  for (const args of calls) {
    const result = await dockerProbe(args, environment);
    if (result.exitCode !== 0) {
      return { exitCode: 72, code: "PREFLIGHT_DOCKER_UNAVAILABLE", freeBytes, thresholdBytes };
    }
    outputs.push(`${result.stdout}\n${result.stderr}`);
  }
  const dbListed = outputs[2].split("\n").some((line) => line.startsWith(`${LOCAL_AUTH_DB_CONTAINER}|`));
  let databaseState = "NOT_RUNNING";
  if (dbListed) {
    const inspectArgs = [
      "inspect", "--format",
      "{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{end}}",
      LOCAL_AUTH_DB_CONTAINER,
    ];
    const logArgs = ["logs", "--tail", "200", LOCAL_AUTH_DB_CONTAINER];
    const inspected = await dockerProbe(inspectArgs, environment);
    const logs = await dockerProbe(logArgs, environment);
    if (inspected.exitCode !== 0 || logs.exitCode !== 0) {
      return { exitCode: 72, code: "PREFLIGHT_DOCKER_HEALTH_UNREADABLE", freeBytes, thresholdBytes };
    }
    outputs.push(`${inspected.stdout}\n${inspected.stderr}`, `${logs.stdout}\n${logs.stderr}`);
    const state = inspected.stdout.trim();
    databaseState = state;
    if (!state.startsWith("running|") || state.endsWith("|unhealthy")) {
      return { exitCode: 74, code: "PREFLIGHT_LOCAL_DATABASE_UNHEALTHY", freeBytes, thresholdBytes };
    }
  }
  if (CORRUPTION_PATTERN.test(outputs.join("\n"))) {
    return { exitCode: 74, code: "PREFLIGHT_DOCKER_STORAGE_UNSAFE", freeBytes, thresholdBytes };
  }
  return {
    exitCode: 0,
    code: "PREFLIGHT_PASS",
    freeBytes,
    thresholdBytes,
    docker: "AVAILABLE",
    databaseState,
    writableHealthSignal: "NO_READ_ONLY_IO_OR_WAL_FSYNC_MARKER_OBSERVED",
  };
}

function localAuthEnvironment(environment) {
  return {
    ...environment,
    DOCKER_BIN: resolveTool("docker", environment),
    SUPABASE_BIN: resolveTool("supabase", environment),
    PHASE021_DB_CONTAINER: LOCAL_AUTH_DB_CONTAINER,
    PHASE022_DB_CONTAINER: LOCAL_AUTH_DB_CONTAINER,
    PHASE023_DB_CONTAINER: LOCAL_AUTH_DB_CONTAINER,
    PHASE024_DB_CONTAINER: LOCAL_AUTH_DB_CONTAINER,
  };
}

async function waitForPostgres(docker, name, environment) {
  const deadline = Date.now() + 30_000;
  let consecutiveReadyChecks = 0;
  while (Date.now() < deadline) {
    const result = await spawnCapture(docker, [
      "exec", name, "pg_isready", "-U", "postgres", "-d", "postgres",
    ], { cwd: REPOSITORY_ROOT, env: environment });
    if (result.exitCode === 0) {
      consecutiveReadyChecks += 1;
      // The official Postgres image briefly exposes its initialization server
      // before replacing it with the final server. Require a stable window so
      // a gate never starts psql during that handoff.
      if (consecutiveReadyChecks >= 4) return 0;
    } else {
      consecutiveReadyChecks = 0;
    }
    await new Promise((resolveDelay) => setTimeout(resolveDelay, 250));
  }
  return 74;
}

async function runDockerPostgres(id, spec, environment) {
  const docker = resolveTool("docker", environment);
  const name = `phase4-gate-${id.replaceAll(".", "-")}`;
  const existing = await spawnCapture(docker, ["inspect", name], {
    cwd: REPOSITORY_ROOT,
    env: environment,
  });
  if (existing.exitCode === 0) return { exitCode: 73, code: "DISPOSABLE_CONTAINER_NAME_IN_USE" };
  const started = await spawnInherit(docker, [
    "run", "--detach", "--rm", "--name", name,
    "--tmpfs", "/var/lib/postgresql/data:rw",
    "--env", "POSTGRES_HOST_AUTH_METHOD=trust",
    "--volume", `${REPOSITORY_ROOT}:/workspace:ro`,
    `postgres:${spec.major}`,
  ], { cwd: REPOSITORY_ROOT, env: environment });
  if (started.exitCode !== 0) return started;

  let primary = { exitCode: await waitForPostgres(docker, name, environment) };
  try {
    if (primary.exitCode !== 0) {
      // The finally block still removes the exact disposable container.
    } else if (spec.scenario === "non-super-clean") {
      primary = await spawnInherit(docker, [
        "exec", name, "bash",
        "/workspace/supabase/tests/_phase024_non_super_runner_regression.sh",
        "/workspace",
      ], { cwd: REPOSITORY_ROOT, env: environment });
    } else if (spec.scenario === "sql-files") {
      const files = ["supabase/tests/_bootstrap_local.sql", ...spec.files];
      for (const file of files) {
        primary = await spawnInherit(docker, [
          "exec", name, "psql", "-X", "-q", "-U", "postgres", "-d", "postgres",
          "-v", "ON_ERROR_STOP=1", "-f", `/workspace/${file}`,
        ], { cwd: REPOSITORY_ROOT, env: environment });
        if (primary.exitCode !== 0) break;
      }
    } else {
      primary = { exitCode: 70, code: "CATALOG_SCENARIO_REJECTED" };
    }
  } finally {
    const cleanup = await spawnCapture(docker, ["stop", "--time", "3", name], {
      cwd: REPOSITORY_ROOT,
      env: environment,
    });
    if (primary.exitCode === 0 && cleanup.exitCode !== 0) primary = cleanup;
  }
  return primary;
}

async function runLocalAuthSequence(spec, environment) {
  const childEnvironment = localAuthEnvironment(environment);
  for (const script of spec.scripts) {
    const result = await spawnInherit(process.execPath, [safeRepositoryPath(script)], {
      cwd: REPOSITORY_ROOT,
      env: childEnvironment,
    });
    if (result.exitCode !== 0) return result;
  }
  return { exitCode: 0 };
}

async function waitForLocalAuth(docker, environment) {
  const deadline = Date.now() + 30_000;
  while (Date.now() < deadline) {
    const result = await spawnCapture(docker, [
      "inspect", "--format",
      "{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{end}}",
      LOCAL_AUTH_CONTAINER,
    ], { cwd: REPOSITORY_ROOT, env: environment });
    const state = result.stdout.trim();
    if (result.exitCode === 0 && state.startsWith("running|") && !state.endsWith("|starting")) return 0;
    await new Promise((resolveDelay) => setTimeout(resolveDelay, 250));
  }
  return 74;
}

async function runLocalAuthRestart(spec, environment) {
  const docker = resolveTool("docker", environment);
  const restarted = await spawnInherit(docker, ["restart", LOCAL_AUTH_CONTAINER], {
    cwd: REPOSITORY_ROOT,
    env: environment,
  });
  if (restarted.exitCode !== 0) return restarted;
  const healthy = await waitForLocalAuth(docker, environment);
  if (healthy !== 0) return { exitCode: healthy, code: "LOCAL_AUTH_RESTART_UNHEALTHY" };
  return spawnInherit(process.execPath, [safeRepositoryPath(spec.script)], {
    cwd: REPOSITORY_ROOT,
    env: localAuthEnvironment(environment),
  });
}

async function sha256(path) {
  return createHash("sha256").update(await readFile(path)).digest("hex");
}

async function runRuntimeReproducibility(environment) {
  const built = await spawnInherit(resolveTool("pnpm", environment), ["bundle:edge"], {
    cwd: safeRepositoryPath("packages/fit-engine-adapter"),
    env: environment,
  });
  if (built.exitCode !== 0) return built;
  const actual = await sha256(safeRepositoryPath("supabase/functions/_shared/fit-runtime.js"));
  return actual === FROZEN_FIT_RUNTIME_SHA256
    ? { exitCode: 0 }
    : { exitCode: 1, code: "FROZEN_RUNTIME_SHA_MISMATCH" };
}

async function runFrozenAudit(environment) {
  const result = await spawnCapture(resolveTool("git", environment), [
    "diff", "--name-only", "HEAD", "--", ...FROZEN_AUDIT_PATHS,
  ], { cwd: REPOSITORY_ROOT, env: environment });
  if (result.exitCode !== 0) return result;
  if (result.stdout.trim().length > 0) return { exitCode: 1, code: "FROZEN_PATH_DRIFT" };
  const actual = await sha256(safeRepositoryPath("supabase/functions/_shared/fit-runtime.js"));
  return actual === FROZEN_FIT_RUNTIME_SHA256
    ? { exitCode: 0 }
    : { exitCode: 1, code: "FROZEN_RUNTIME_SHA_MISMATCH" };
}

async function runReleaseOps(environment) {
  const projectRef = environment.PHASE4_RELEASE_PROJECT_REF ?? "";
  if (!PROJECT_REF_PATTERN.test(projectRef)) {
    return { exitCode: 64, code: "RELEASE_PROJECT_REF_INVALID" };
  }
  if (typeof environment.SUPABASE_ACCESS_TOKEN !== "string" ||
      environment.SUPABASE_ACCESS_TOKEN.length === 0) {
    return { exitCode: 64, code: "RELEASE_ACCESS_TOKEN_MISSING" };
  }
  return spawnInherit(process.execPath, [
    safeRepositoryPath("scripts/phase4a2-minimum-beta-ops.mjs"),
    "--project-ref", projectRef,
    "--include-database",
  ], { cwd: REPOSITORY_ROOT, env: environment });
}

export async function executeCatalogCommand(id, spec, context = {}) {
  const environment = context.environment ?? process.env;
  if (spec.kind === "preflight") {
    return runReadOnlyPreflight({
      diskClass: spec.diskClass,
      requireDocker: spec.requireDocker,
      freeBytesProvider: context.freeBytesProvider,
      dockerProbe: context.dockerProbe,
      environment,
    });
  }
  if (spec.kind === "spawn") {
    return spawnInherit(resolveTool(spec.tool, environment), spec.args, {
      cwd: safeRepositoryPath(spec.cwd),
      env: environment,
    });
  }
  if (spec.kind === "docker-postgres") return runDockerPostgres(id, spec, environment);
  if (spec.kind === "local-auth-sequence") return runLocalAuthSequence(spec, environment);
  if (spec.kind === "local-auth-restart") return runLocalAuthRestart(spec, environment);
  if (spec.kind === "runtime-reproducibility") return runRuntimeReproducibility(environment);
  if (spec.kind === "frozen-audit") return runFrozenAudit(environment);
  if (spec.kind === "release-ops") return runReleaseOps(environment);
  if (spec.kind === "authorization-hold") return { exitCode: 78, code: spec.code };
  return { exitCode: 70, code: "CATALOG_COMMAND_KIND_REJECTED" };
}

function defaultReporter(event) {
  const safe = {
    event: event.event,
    gate: event.gate,
    command: event.command,
    classification: event.classification,
    status: event.status,
    exitCode: event.exitCode,
    durationMs: event.durationMs,
    code: event.code,
    freeBytes: event.freeBytes,
    thresholdBytes: event.thresholdBytes,
  };
  const bounded = Object.fromEntries(Object.entries(safe).filter(([, value]) => value !== undefined));
  process.stdout.write(`${JSON.stringify(bounded)}\n`);
}

export async function runResolvedCommands({
  gateName,
  commands,
  executor = executeCatalogCommand,
  reporter = defaultReporter,
  now = () => Date.now(),
  context = {},
}) {
  const gateStarted = now();
  for (const command of commands) {
    const commandStarted = now();
    let result;
    try {
      result = await executor(command.id, command.spec, context);
    } catch {
      result = { exitCode: 70, code: "COMMAND_EXECUTION_FAILED_CLOSED" };
    }
    if (!Number.isInteger(result?.exitCode) || result.exitCode < 0) {
      result = { exitCode: 70, code: "COMMAND_EXIT_CODE_INVALID" };
    }
    const durationMs = Math.max(0, now() - commandStarted);
    reporter({
      event: "COMMAND_TIMING",
      gate: gateName,
      command: command.id,
      classification: command.spec.classification,
      status: result.exitCode === 0 ? "PASS" : "FAIL",
      exitCode: result.exitCode,
      durationMs,
      code: result.code,
      freeBytes: result.freeBytes,
      thresholdBytes: result.thresholdBytes,
    });
    if (result.exitCode !== 0) {
      const gateDurationMs = Math.max(0, now() - gateStarted);
      reporter({
        event: "GATE_TIMING",
        gate: gateName,
        status: "FAIL",
        exitCode: result.exitCode,
        durationMs: gateDurationMs,
        code: result.code,
      });
      return { exitCode: result.exitCode, failedCommand: command.id, durationMs: gateDurationMs };
    }
  }
  const durationMs = Math.max(0, now() - gateStarted);
  reporter({ event: "GATE_TIMING", gate: gateName, status: "PASS", exitCode: 0, durationMs });
  return { exitCode: 0, durationMs };
}

export async function runGate(manifest, gateName, options = {}) {
  validateManifest(manifest, options.catalog ?? COMMAND_CATALOG);
  return runResolvedCommands({
    gateName,
    commands: resolveGate(manifest, gateName, options.catalog ?? COMMAND_CATALOG),
    executor: options.executor,
    reporter: options.reporter,
    now: options.now,
    context: options.context,
  });
}

export async function executeMode(manifest, mode, gateName, options = {}) {
  validateManifest(manifest, options.catalog ?? COMMAND_CATALOG);
  if (mode === "dry-run" || mode === "explain") {
    return {
      exitCode: 0,
      output: formatGatePlan(manifest, gateName, mode, options.catalog ?? COMMAND_CATALOG),
    };
  }
  if (mode === "run") return runGate(manifest, gateName, options);
  if (mode === "preflight") {
    const preflight = resolveGate(manifest, gateName, options.catalog ?? COMMAND_CATALOG)
      .filter(({ spec }) => spec.kind === "preflight");
    if (preflight.length !== 1) fail("PREFLIGHT_COMMAND_CARDINALITY_INVALID");
    return runResolvedCommands({
      gateName,
      commands: preflight,
      executor: options.executor,
      reporter: options.reporter,
      now: options.now,
      context: options.context,
    });
  }
  fail("CLI_MODE_REJECTED");
}

export function parseCli(argv) {
  if (!Array.isArray(argv) || argv.length < 1 || argv.length > 2) fail("CLI_ARGUMENTS_REJECTED");
  const [mode, gateName] = argv;
  if (mode === "validate") {
    if (argv.length !== 1) fail("CLI_ARGUMENTS_REJECTED");
    return { mode, gateName: null };
  }
  if (!["run", "dry-run", "explain", "preflight"].includes(mode) || argv.length !== 2) {
    fail("CLI_ARGUMENTS_REJECTED");
  }
  if (!GATE_NAMES.includes(gateName)) fail("MANIFEST_UNKNOWN_GATE");
  return { mode, gateName };
}

export async function main(argv = process.argv.slice(2)) {
  try {
    const { mode, gateName } = parseCli(argv);
    const manifest = await loadManifest();
    validateManifest(manifest);
    await validateCatalogReferences();
    if (mode === "validate") {
      process.stdout.write("PHASE4_LAYERED_GATE_MANIFEST_V1_VALID\n");
      return 0;
    }
    const result = await executeMode(manifest, mode, gateName);
    if (result.output) process.stdout.write(result.output);
    return result.exitCode;
  } catch (error) {
    const code = error instanceof LayeredGateError ? error.code : "LAYERED_GATE_FAILED_CLOSED";
    process.stdout.write(`${JSON.stringify({ event: "LAYERED_GATE_ERROR", code })}\n`);
    return 64;
  }
}

const invokedPath = process.argv[1] ? pathToFileURL(resolve(process.argv[1])).href : null;
if (invokedPath === import.meta.url) process.exitCode = await main();

export { SAFE_DOCKER_PREFLIGHT_ACTIONS };
