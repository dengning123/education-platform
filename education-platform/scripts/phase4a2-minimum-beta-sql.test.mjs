import assert from "node:assert/strict";
import test from "node:test";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  DATABASE_CHECK_CODES,
  OperationalCheckError,
  validateReadOnlySqlPack,
} from "./phase4a2-minimum-beta-ops.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const sqlPath = resolve(here, "../supabase/snippets/phase4a2_minimum_beta_invariants.sql");

test("query pack has an explicit read-only transaction and exact fixed check set", async () => {
  const sql = await readFile(sqlPath, "utf8");
  const query = validateReadOnlySqlPack(sql);
  assert.match(sql, /^begin read only;/i);
  assert.match(sql.trim(), /rollback;$/i);
  assert.match(query, /^with\s+invariant_counts/i);
  for (const code of DATABASE_CHECK_CODES) {
    assert.equal((sql.match(new RegExp(`'${code}'`, "g")) ?? []).length, 1);
  }
});

test("query pack returns only check_code and violation_count", async () => {
  const sql = await readFile(sqlPath, "utf8");
  const query = validateReadOnlySqlPack(sql);
  assert.match(query, /select invariant\.check_code, invariant\.violation_count\s+from invariant_counts/i);
  assert.doesNotMatch(query, /\bselect\s+\*/i);
  assert.doesNotMatch(query, /\breturning\b/i);
  assert.doesNotMatch(query, /\bfor\s+update\b/i);
});

test("query pack covers version-aware eligibility and v015 Fit semantic pins", async () => {
  const sql = await readFile(sqlPath, "utf8");
  assert.match(sql, /input_schema_version = 'eligibility-v0\.1'/);
  assert.match(sql, /input_schema_version = 'eligibility-v0\.2'/);
  assert.match(sql, /private\.fit_evaluation_semantic_pins/);
  assert.match(sql, /replay_contract_version = 'FIT_REPLAY_SEAL_V015'/);
});

test("query pack covers verified normalization source, semantic pin, method, input, and factor graph", async () => {
  const sql = await readFile(sqlPath, "utf8");
  for (const fragment of [
    "private.fit_financial_source_pins_v014",
    "private.fit_financial_normalization_verified_pins_v014",
    "public.fit_financial_normalization_methods",
    "public.fit_financial_conversion_inputs_v014",
    "public.fit_financial_conversion_factors_v014",
  ]) assert.equal(sql.includes(fragment), true);
});

test("adversarial SQL cannot hide a write in comments or string boundaries", () => {
  const malicious = `
    begin read only;
    -- PHASE4A2_COUNT_QUERY_BEGIN
    with x as (select 'FIT_STALE_BUILDING_GT_15M'::text as check_code, 0::bigint as violation_count)
    delete from public.fit_evaluations;
    -- PHASE4A2_COUNT_QUERY_END
    rollback;
  `;
  assert.throws(
    () => validateReadOnlySqlPack(malicious),
    (error) => error instanceof OperationalCheckError && error.code === "SQL_PACK_MUTATION_OR_BROAD_READ",
  );
});
