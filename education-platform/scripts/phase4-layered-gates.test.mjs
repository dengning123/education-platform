import assert from "node:assert/strict";
import test from "node:test";

import {
  COMMAND_CATALOG,
  GATE_REQUIRED_ORDERS,
  HEAVY_MIN_FREE_BYTES,
} from "./phase4-layered-gates.catalog.mjs";
import {
  LayeredGateError,
  SAFE_DOCKER_PREFLIGHT_ACTIONS,
  executeMode,
  formatGatePlan,
  loadManifest,
  parseCli,
  resolveGate,
  runGate,
  runReadOnlyPreflight,
  validateCatalogReferences,
  validateManifest,
} from "./phase4-layered-gates.mjs";

const manifest = await loadManifest();

function copy(value) {
  return structuredClone(value);
}

function rejectsCode(action, code) {
  assert.throws(
    action,
    (error) => error instanceof LayeredGateError && error.code === code,
  );
}

test("validates the closed FAST, RELEVANT, BASELINE, and RELEASE manifest", async () => {
  assert.equal(validateManifest(manifest), manifest);
  assert.equal(await validateCatalogReferences(), true);
  assert.deepEqual(Object.keys(manifest.gates), ["FAST", "RELEVANT", "BASELINE", "RELEASE"]);
});

test("unknown gate names fail closed", () => {
  rejectsCode(() => resolveGate(manifest, "FAST;rm"), "MANIFEST_UNKNOWN_GATE");
  rejectsCode(() => parseCli(["run", "UNKNOWN"]), "MANIFEST_UNKNOWN_GATE");
});

test("unknown command references fail closed", () => {
  const changed = copy(manifest);
  changed.gates.FAST.commands[1].id = "unknown.command";
  rejectsCode(() => validateManifest(changed), "MANIFEST_UNKNOWN_COMMAND");
});

test("manifest and command execution order is deterministic", () => {
  for (const gate of ["FAST", "RELEVANT", "BASELINE"]) {
    const first = resolveGate(manifest, gate).map(({ id }) => id);
    const second = resolveGate(manifest, gate).map(({ id }) => id);
    assert.deepEqual(first, GATE_REQUIRED_ORDERS[gate]);
    assert.deepEqual(second, first);
  }
  assert.deepEqual(
    resolveGate(manifest, "RELEASE").map(({ id }) => id),
    [...GATE_REQUIRED_ORDERS.BASELINE, ...GATE_REQUIRED_ORDERS.RELEASE],
  );
});

test("required command failure stops the gate and propagates the exact exit code", async () => {
  const called = [];
  const events = [];
  const result = await runGate(manifest, "FAST", {
    executor: async (id) => {
      called.push(id);
      return { exitCode: called.length === 2 ? 23 : 0 };
    },
    reporter: (event) => events.push(event),
  });
  assert.equal(result.exitCode, 23);
  assert.equal(result.failedCommand, GATE_REQUIRED_ORDERS.FAST[1]);
  assert.deepEqual(called, GATE_REQUIRED_ORDERS.FAST.slice(0, 2));
  assert.equal(events.at(-1).event, "GATE_TIMING");
  assert.equal(events.at(-1).exitCode, 23);
});

test("dry-run executes no command and lists exact identities", async () => {
  let executions = 0;
  const result = await executeMode(manifest, "dry-run", "RELEVANT", {
    executor: async () => {
      executions += 1;
      return { exitCode: 0 };
    },
  });
  assert.equal(executions, 0);
  assert.match(result.output, /^MODE=DRY_RUN/m);
  for (const id of GATE_REQUIRED_ORDERS.RELEVANT) assert.match(result.output, new RegExp(id.replaceAll(".", "\\.")));
  assert.match(result.output, /EXECUTION=NONE/);
});

test("explain output includes reasons, prerequisites, order, and heavy classification", () => {
  const output = formatGatePlan(manifest, "BASELINE", "explain");
  assert.match(output, /^MODE=EXPLAIN/m);
  assert.match(output, /^CLASSIFICATION=heavy/m);
  assert.match(output, /PREREQUISITES:/);
  assert.match(output, /EXECUTION_ORDER:/);
  assert.match(output, /why: Prove the full PostgreSQL 15 non-superuser clean migration runner path through Migration 025\./);
  assert.match(output, /db\.pg15-clean-001-025-non-super \[heavy\]/);
  assert.match(output, /EXECUTION=NONE/);
});

test("heavy preflight fails closed below the fixed disk threshold before Docker", async () => {
  let dockerCalls = 0;
  const result = await runReadOnlyPreflight({
    diskClass: "heavy",
    requireDocker: true,
    freeBytesProvider: async () => HEAVY_MIN_FREE_BYTES - 1,
    dockerProbe: async () => {
      dockerCalls += 1;
      return { exitCode: 0, stdout: "", stderr: "" };
    },
  });
  assert.equal(result.exitCode, 75);
  assert.equal(result.code, "PREFLIGHT_DISK_BELOW_THRESHOLD");
  assert.equal(dockerCalls, 0);
});

test("Docker preflight uses only read-only commands and emits no raw logs", async () => {
  const calls = [];
  const secret = "Bearer secret-jwt-must-not-appear";
  const dockerProbe = async (args) => {
    calls.push(args);
    const action = args[0];
    if (action === "version") return { exitCode: 0, stdout: "27.1.1\n", stderr: "" };
    if (action === "info") return { exitCode: 0, stdout: "[]\n", stderr: "" };
    if (action === "ps") {
      return {
        exitCode: 0,
        stdout: "supabase_db_capibara-education-platform|Up 1 minute (healthy)\n",
        stderr: "",
      };
    }
    if (action === "inspect") return { exitCode: 0, stdout: "running|healthy\n", stderr: "" };
    if (action === "logs") return { exitCode: 0, stdout: `ordinary local log ${secret}\n`, stderr: "" };
    throw new Error("unexpected probe");
  };
  const result = await runReadOnlyPreflight({
    diskClass: "heavy",
    requireDocker: true,
    freeBytesProvider: async () => HEAVY_MIN_FREE_BYTES + 1024,
    dockerProbe,
  });
  assert.equal(result.exitCode, 0);
  assert.equal(result.writableHealthSignal, "NO_READ_ONLY_IO_OR_WAL_FSYNC_MARKER_OBSERVED");
  assert.equal(JSON.stringify(result).includes(secret), false);
  for (const args of calls) {
    assert.equal(SAFE_DOCKER_PREFLIGHT_ACTIONS.has(args[0]), true);
    assert.equal(["run", "exec", "start", "stop", "restart", "rm", "prune"].includes(args[0]), false);
  }
});

test("Docker preflight rejects read-only, I/O, ext4, and WAL fsync markers", async () => {
  const dockerProbe = async (args) => {
    if (args[0] === "ps") {
      return { exitCode: 0, stdout: "supabase_db_capibara-education-platform|Up (healthy)\n", stderr: "" };
    }
    if (args[0] === "inspect") return { exitCode: 0, stdout: "running|healthy\n", stderr: "" };
    if (args[0] === "logs") return { exitCode: 0, stdout: "WAL fsync I/O error", stderr: "" };
    return { exitCode: 0, stdout: "[]\n", stderr: "" };
  };
  const result = await runReadOnlyPreflight({
    diskClass: "heavy",
    requireDocker: true,
    freeBytesProvider: async () => HEAVY_MIN_FREE_BYTES + 1024,
    dockerProbe,
  });
  assert.equal(result.exitCode, 74);
  assert.equal(result.code, "PREFLIGHT_DOCKER_STORAGE_UNSAFE");
});

test("timing records every command and the gate total without changing behavior", async () => {
  const events = [];
  let tick = 0;
  const result = await runGate(manifest, "FAST", {
    executor: async () => ({ exitCode: 0 }),
    reporter: (event) => events.push(event),
    now: () => {
      tick += 10;
      return tick;
    },
  });
  assert.equal(result.exitCode, 0);
  const commands = events.filter(({ event }) => event === "COMMAND_TIMING");
  assert.equal(commands.length, GATE_REQUIRED_ORDERS.FAST.length);
  assert.equal(commands.every(({ durationMs, status }) => durationMs === 10 && status === "PASS"), true);
  const total = events.at(-1);
  assert.equal(total.event, "GATE_TIMING");
  assert.equal(total.status, "PASS");
  assert.equal(total.durationMs > commands[0].durationMs, true);
});

test("tool-owned dry-run and timing output is secret-safe", async () => {
  const secret = "service-role-secret-never-print";
  const output = formatGatePlan(manifest, "RELEASE", "dry-run");
  const events = [];
  await runGate(manifest, "FAST", {
    executor: async () => ({ exitCode: 0, raw: secret }),
    reporter: (event) => events.push(JSON.stringify(event)),
    context: { environment: { SUPABASE_ACCESS_TOKEN: secret } },
  });
  assert.equal(output.includes(secret), false);
  assert.equal(events.join("\n").includes(secret), false);
  assert.match(output, /<validated-env>/);
});

test("BASELINE cannot be weakened by configuration", () => {
  const changed = copy(manifest);
  changed.gates.BASELINE.commands.splice(5, 1);
  rejectsCode(() => validateManifest(changed), "MANIFEST_BASELINE_RIGOR_WEAKENED");

  const skipChanged = copy(manifest);
  skipChanged.policy.baselineChangedPathSkipping = true;
  rejectsCode(() => validateManifest(skipChanged), "MANIFEST_FAIL_CLOSED_POLICY_WEAKENED");
});

test("RELEASE is always a strict BASELINE superset", () => {
  const changed = copy(manifest);
  changed.gates.RELEASE.commands.pop();
  rejectsCode(() => validateManifest(changed), "MANIFEST_RELEASE_RIGOR_WEAKENED");

  const detached = copy(manifest);
  detached.gates.RELEASE.extends = "RELEVANT";
  rejectsCode(() => validateManifest(detached), "MANIFEST_RELEASE_NOT_BASELINE_SUPERSET");
});

test("unknown references and shell-shaped manifest entries fail closed", async () => {
  const catalog = copy(COMMAND_CATALOG);
  catalog["repo.diff-check"].files = ["../outside-repository"];
  await assert.rejects(
    validateCatalogReferences(catalog),
    (error) => error instanceof LayeredGateError && error.code === "CATALOG_REFERENCE_OUTSIDE_REPOSITORY",
  );

  const injected = copy(manifest);
  injected.gates.FAST.commands[0].shell = "rm -rf /";
  rejectsCode(() => validateManifest(injected), "MANIFEST_FAST_COMMAND_ENTRY_CLOSED");
});

test("catalog exposes no shell execution surface and CLI accepts no free-form command", () => {
  for (const spec of Object.values(COMMAND_CATALOG)) {
    assert.equal(Object.hasOwn(spec, "shell"), false);
    if (spec.kind === "spawn") {
      assert.equal(["node", "pnpm", "npm", "git", "supabase"].includes(spec.tool), true);
      assert.equal(Array.isArray(spec.args), true);
    }
  }
  rejectsCode(() => parseCli(["run", "FAST", "echo secret"]), "CLI_ARGUMENTS_REJECTED");
  rejectsCode(() => parseCli(["shell", "FAST"]), "CLI_ARGUMENTS_REJECTED");
});
