# Phase 3 Financial Billing-Basis Hardening — Migration 014 Plan

**Status:** Planning only; final contract review required  
**Authorized migration:** `014` only  
**Frozen inputs:** migrations `001`–`013`; no edits of any kind  
**Excluded:** Fit Engine and every object or behavior in quarantined untracked `015_fit_replay_and_seal_hardening.sql`

## 1. Defect and closed boundary

Migration 011 hard-codes every selected `PROGRAM_COST` amount as `ACADEMIC_YEAR`. Migration 014 may only correct Financial source authority, comparability, normalization evidence, and the corresponding v014 input-fingerprint contract. It does not calculate an assessment, choose direction, compare amounts, aggregate components, infer credits/duration, or perform a conversion.

014 replaces only these frozen functions: `public.validate_fit_financial_normalization()`, `public.compute_fit_decision_input_fingerprint(uuid)`, and the Financial admissibility branch of `public.finalize_fit_evaluation(uuid)`. New 014 triggers and entry points may call the unchanged frozen assembly authorization/insert framework. It does not replace sealing/result-fingerprint/replay architecture and must not copy, rename, call, or depend on a 015 object.

## 2. Closed billing-basis mapping

| authoritative basis | mapped Fit period |
|---|---|
| `TOTAL_PROGRAM` | `PROGRAM_DURATION` |
| `PER_YEAR` | `ACADEMIC_YEAR` |
| `PER_SEMESTER` | `ACADEMIC_SEMESTER` |
| `PER_CREDIT` | `CREDIT` |
| `UNKNOWN` | SQL `NULL` |
| SQL `NULL` | SQL `NULL` |

There is no default mapping and no period/currency/scope/basis/component conversion. Add `ACADEMIC_SEMESTER` and `CREDIT` to `public.fit_financial_period`. Add immutable, strict `public.fit_financial_period_for_billing_basis(public.billing_basis)`. Its explicit `CASE` lists all five enum labels, returns null only for `UNKNOWN`, has no `ELSE`, and raises `22023` for any future non-null unmapped label. `STRICT` supplies null for SQL null. An enum-exhaustiveness test compares `enum_range` with the five named labels.

014 is exactly one file, `202608200014_financial_billing_basis_hardening.sql`, with top-level `BEGIN;` + the two enum alterations + `COMMIT;`, followed by `BEGIN;` + preflight/object phase + `COMMIT;`. It contains no procedure/function wrapping those transaction commands. This is the repository's `psql -v ON_ERROR_STOP=1 -f` execution model and ensures new labels are committed before use. Before any object is authored, run a disposable probe containing this exact transaction shape through both installed Supabase `db reset` and the README `psql -f` path. Success is an implementation prerequisite; failure means **BLOCKED—runner cannot execute the approved 014 contract** and requires plan review. Splitting/renumbering, relying on an outer transaction, or consuming 015 is forbidden.

## 3. Independent billing-basis authority

An amount observation never authorizes `billing_basis`. For each normalization, 014 pins two distinct canonical observations on the same active `PROGRAM_COST` row:

- amount observation: selected `KNOWN`, numeric, field in `tuition_amount`, `mandatory_fees`, `estimated_living_cost`, `estimated_total_cost`;
- basis observation: selected `KNOWN`, field exactly `billing_basis`, JSON string exactly equal to the typed `program_costs.billing_basis`, and one of the four mapped known labels.

Both observations must have an applicability row whose current head assertion is `APPLICABLE`, must reference non-null evidence, and must be present as distinct `CATALOG_FIELD_OBSERVATION` manifest items for the evaluation's Financial method. The same material deterministic Financial signal must link through `fit_signal_evidence` to the amount item, basis item, exact constraint item, and—when used—the normalization item. The basis selection key is exactly `(record_type='PROGRAM_COST', record_id=cost_id, field_name='billing_basis')`.

Missing selection, non-`KNOWN`, `UNKNOWN`, SQL null, stale, `SOURCE_CONFLICT`, non-applicable/legacy-unasserted applicability, mismatched live typed value, mismatched record, retired cost row, absent manifest item, or wrong signal link is inadmissible. No live `program_costs.billing_basis` value supplies authority without this chain.

## 4. Exact source tuple and direct comparability

The authoritative source tuple is derived, never evaluator-selected:

```text
amount     = selected amount observation numeric value
currency   = program_costs.currency
period     = map(selected basis observation value)
scope      = TOTAL_COST only for estimated_total_cost; otherwise COMPONENT
basis      = GROSS
components = tuition_amount        -> {TUITION}
             mandatory_fees        -> {MANDATORY_FEES}
             estimated_living_cost -> {LIVING_COST}
             estimated_total_cost  -> {TOTAL_COST}
```

`public.fit_financial_facts_directly_comparable(...)` is immutable and returns true iff mapped source period and target period, currency, scope, basis, and canonical component sets are all exactly equal. Amount does **not** participate: it is the value compared only by the external evaluator after admissibility is established. Required nulls return false. Arrays are sets: existing checks prohibit null/empty elements and duplicates; the predicate sorts both arrays, treats order as irrelevant, and requires exact equality. Null/empty arrays return false.

`AVAILABLE_FUNDING` is never a cost ceiling and cannot be directly compared with a gross program-cost fact. It may participate only as the funding input of a verified normalization whose output basis is `NET_OF_VERIFIED_FUNDING`; it cannot be the target constraint used to claim a supporting/contradicting cost-ceiling signal. A directional net-cost signal requires (a) a ceiling/preference target declaration and (b) a separate `AVAILABLE_FUNDING` declaration, both in the frozen intent set and both linked to the same signal. Gross-to-gross normalizations must not reference funding. SQL validates provenance and declared arithmetic inputs but never evaluates whether an amount satisfies a ceiling.

## 5. Exact additive schema

### 5.1 Persisted v014 discriminator

Add nullable `financial_contract_version text` to `public.fit_evaluations`, with check `IS NULL OR = 'FINANCIAL_BILLING_BASIS_V014'`. Existing rows remain null. A 014 `BEFORE INSERT` trigger always overwrites the new value with the literal, so every evaluation created after installation is v014 without replacing `start_fit_evaluation`. Add `public.adopt_fit_financial_contract_v014(uuid)` for the one permitted legacy BUILDING/no-child/no-candidate case; it requires the existing transaction-bound assembly authorization. The evaluation guard permits null-to-v014 only while that function sets a transaction-local private flag and forbids every later change. Finalization branches solely on the persisted value. No timestamp, fingerprint inspection, row absence, or UUID shape may classify a row. Pre-014 compatibility is solely `NULL = legacy`, literal = v014.

### 5.2 Basis and source provenance pin

Create `private.fit_financial_source_pins_v014` with exactly:

```text
source_pin_id uuid PK DEFAULT gen_random_uuid()
evaluation_id uuid NOT NULL
amount_manifest_item_id uuid NOT NULL
basis_manifest_item_id uuid NOT NULL
amount_observation_id uuid NOT NULL
billing_basis_observation_id uuid NOT NULL
cost_id uuid NOT NULL
source_billing_basis billing_basis NOT NULL CHECK <> UNKNOWN
source_mapped_period fit_financial_period NOT NULL
amount_selection_selected_at timestamptz NOT NULL
basis_selection_selected_at timestamptz NOT NULL
amount_observation_payload_hash text NOT NULL CHECK sha256
basis_observation_payload_hash text NOT NULL CHECK sha256
amount_evidence_payload_hash text NOT NULL CHECK sha256
basis_evidence_payload_hash text NOT NULL CHECK sha256
amount_applicability_payload_hash text NOT NULL CHECK sha256
basis_applicability_payload_hash text NOT NULL CHECK sha256
cost_payload_hash text NOT NULL CHECK sha256
pinned_at timestamptz NOT NULL DEFAULT transaction_timestamp()
UNIQUE(evaluation_id,amount_manifest_item_id,basis_manifest_item_id)
UNIQUE(evaluation_id,source_pin_id)
CHECK(amount_observation_id <> billing_basis_observation_id)
```

Add nullable `source_pin_id uuid` to the frozen normalization table, with composite FK `(evaluation_id,source_pin_id)` to this table; legacy rows remain null and v014 rows require non-null. The assembly-only security-definer entry point `public.pin_fit_financial_source_v014(evaluation_id,amount_manifest_item_id,basis_manifest_item_id)` returns `source_pin_id`, derives all values after locking evaluation, manifests, cost, selections, observations, applicability heads/assertions and evidence in section 8 order, and inserts exactly once. It requires the persisted v014 discriminator and matching Financial method/profile/program. Callers cannot provide pin values. This independent evaluation-scoped pin is mandatory for both direct and normalized branches; a normalization references it rather than owning it.

### 5.3 Normalization lifecycle

Create `public.fit_financial_normalization_reviews_v014` with one row per normalization:

```text
financial_normalization_id uuid PK/FK
evaluation_id uuid NOT NULL
status fit_definition_status NOT NULL DEFAULT DRAFT
reviewed_by text
reviewed_at timestamptz
verification_evidence_id uuid FK evidence_items
retired_at timestamptz
retirement_reason text
created_at timestamptz NOT NULL DEFAULT now()
updated_at timestamptz NOT NULL DEFAULT now()
```

Exact states: DRAFT has all review/retirement fields null; VERIFIED requires nonblank reviewer, review timestamp, verification evidence, and no retirement fields; RETIRED preserves review fields and requires retirement timestamp/reason. An `AFTER INSERT` trigger on `fit_financial_normalizations` inserts the sole DRAFT review row; direct review-table INSERT is rejected unless a transaction-local trigger flag is set, so terminal direct insertion is impossible. Only `DRAFT -> VERIFIED -> RETIRED` is allowed; no reverse/skip transition. Verification and retirement occur only through security-definer `public.verify_fit_financial_normalization_v014(uuid,text,uuid)` and `public.retire_fit_financial_normalization_v014(uuid,text)`, callable only by `foundation_catalog_executor`. Verification locks and revalidates the complete normalization and pins its verification evidence hash. Once VERIFIED, normalization payload, typed inputs, source pins, and review fields are immutable; retirement changes only status/retirement fields. Finalization accepts VERIFIED only and rejects RETIRED. A VERIFIED method does not imply a VERIFIED normalization.

The replaced insert-time `validate_fit_financial_normalization()` validates only facts that must exist at normalization insertion: v014 discriminator, BUILDING/unsealed/authorized evaluation, non-null matching source pin, exact source tuple, exact ceiling/preference target tuple, active release-matched VERIFIED method axes, nonempty legacy JSON, and no funding misuse. It cannot require later child rows. The verify entry point, after typed rows exist, validates the closed method/input/factor contract and all hashes before DRAFT->VERIFIED. Finalization repeats the complete verified validation. This is the only staged order: source pin -> normalization (automatic DRAFT) -> typed rows -> verify -> manifest/signal assembly -> seal -> finalize.

### 5.4 Closed typed conversion inputs

Arbitrary `conversion_evidence` JSON is retained only for frozen-row compatibility and presentation; it is not authority under v014. Create:

`public.fit_financial_conversion_factors_v014`:

```text
conversion_factor_id uuid PK
financial_normalization_id uuid NOT NULL FK
factor_ordinal smallint NOT NULL CHECK > 0
factor_code text NOT NULL CHECK ^[A-Z][A-Z0-9_]*$
operation text NOT NULL CHECK IN ('MULTIPLY','DIVIDE','ADD','SUBTRACT')
factor_value numeric NOT NULL
source_unit text NOT NULL
target_unit text NOT NULL
evidence_id uuid NOT NULL FK
UNIQUE(financial_normalization_id,factor_ordinal)
```

`public.fit_financial_conversion_inputs_v014`:

```text
conversion_input_id uuid PK
financial_normalization_id uuid NOT NULL FK
input_ordinal smallint NOT NULL CHECK > 0
input_role text NOT NULL CHECK IN ('SOURCE_AMOUNT','PROGRAM_DURATION','ACADEMIC_YEARS','SEMESTERS','CREDITS','EXCHANGE_RATE','AVAILABLE_FUNDING','ROUNDING')
numeric_value numeric
text_value text
unit text NOT NULL
source_observation_id uuid FK field_observations
intent_declaration_id uuid FK fit_intent_declarations
evidence_id uuid NOT NULL FK evidence_items
UNIQUE(financial_normalization_id,input_ordinal)
CHECK(exactly one of numeric_value,text_value is nonnull)
```

`SOURCE_AMOUNT` must occur exactly once and equal the pinned original amount/observation. `ROUNDING` must occur exactly once, use `text_value` in `NONE`, `HALF_UP`, `HALF_EVEN`, `FLOOR`, `CEILING`, and unit `RULE`. Every other role may occur at most once. `AVAILABLE_FUNDING` must reference the separate funding intent declaration, equal its amount/currency/period/scope/components, and is required iff target basis is `NET_OF_VERIFIED_FUNDING`. Each factor/input evidence payload is hashed in the verified payload. Method `normalization_contract` must contain exact arrays `requiredInputRoles`, `allowedInputRoles`, `requiredFactorCodes`, `allowedFactorCodes`, plus `formulaCode`; equality with typed rows is set-exact—missing and extra rows reject. No free-form key authorizes a conversion.

### 5.5 Semantic identity and payload pin

Create `private.fit_financial_normalization_verified_pins_v014` keyed by normalization id with evaluation id; method payload/evidence hashes; normalization-review evidence hash; typed-input payload hash; typed-factor payload hash; legacy JSON hash; target constraint payload hash; and `verified_at`. All hashes are lowercase SHA-256 over UTF-8 `jsonb::text` from the canonical serializers below.

Add private immutable canonical serializers. Authority/audit payloads are mechanically `to_jsonb(alias)` of the complete frozen/current row, including IDs and all timestamps, with no removed columns: `field_observations`, `canonical_field_selections`, `evidence_items`, `evidence_applicability_heads`, `evidence_applicability_assertions`, `field_observation_applicability`, `program_costs`, `fit_financial_normalization_methods`, `fit_intent_financial_constraints`, the normalization review, and the source/verified pin. A selection/applicability payload is `jsonb_build_object('link',to_jsonb(link_row),'head',to_jsonb(head_row),'assertion',to_jsonb(assertion_row))`. Typed-input and factor payloads are arrays of complete rows ordered by their ordinal; component arrays inside constraint/normalization payloads are replaced by sorted arrays. These full-row payloads are provenance hashes and intentionally change on any upstream row change.

The decision normalization payload uses exactly these keys: `contract`, `profileVersionId`, `intentSetId`, `programVersionId`, `contractReleaseId`, `amountObservationHash`, `basisObservationHash`, `amountSelectionHash`, `basisSelectionHash`, `amountApplicabilityHash`, `basisApplicabilityHash`, `amountEvidenceHash`, `basisEvidenceHash`, `costHash`, `sourceBillingBasis`, `sourceAmount`, `sourceCurrency`, `sourcePeriod`, `sourceScope`, `sourceBasis`, `sourceComponents`, `targetConstraintHash`, `targetAmount`, `targetCurrency`, `targetPeriod`, `targetScope`, `targetBasis`, `targetComponents`, `methodCode`, `methodVersion`, `methodContractHash`, `methodVerificationEvidenceHash`, `normalizationReviewEvidenceHash`, `conversionInputsHash`, `conversionFactorsHash`, and `legacyConversionJsonHash`. `contract` is the literal `FINANCIAL_BILLING_BASIS_V014`; components are sorted. No unlisted key is added to this semantic payload.

The normalization semantic identity excludes all generated/incidental values: normalization UUID, source-pin UUID, manifest UUIDs, conversion input/factor UUIDs, `created_at`, `updated_at`, `pinned_at`, and insertion order. It includes evaluation's profile/intent/program/release identity, both observation semantic payload hashes, cost/basis/source tuple, target constraint semantic payload, method code+version+contract semantic payload, normalized typed rows, evidence payload hashes, amounts, and literal contract marker. Thus independently inserted equivalent v014 inputs fingerprint identically; changing any semantic input changes the hash. Generated IDs remain in audit payloads but never determine the semantic fingerprint.

## 6. Fingerprint and finalization

`private.fit_financial_normalization_payload_v014(uuid)` returns only the semantic payload above. Add `private.fit_financial_source_payload_v014(uuid)` with exactly: `contract`, evaluation profile/intent/program/release identities, amount+basis observation/selection/applicability/evidence hashes, cost hash, and the derived source amount/currency/period/scope/basis/sorted-components tuple; it excludes source-pin and manifest UUIDs/timestamps.

The top-level decision-input JSON always includes persisted `financialContractVersion`. For v014 it includes `financialSources` for every source pin referenced by a Financial signal, ordered by source semantic hash, and `financialNormalizations` ordered by normalization semantic hash. Duplicate semantic hashes in either array reject before hashing; generated UUIDs are not ordering keys or payload fields. Exact set equality between signal-referenced pins and `financialSources`, and between normalization-linked signals and `financialNormalizations`, is required, so unused/extra pins or normalizations reject. Legacy-null evaluations retain the exact v011 serializer and stored fingerprints; 014 does not recompute or relabel them.

Every v014 directional deterministic Financial signal must prove exactly one admissibility branch:

1. direct: exact source/target predicate true, with amount+basis+constraint manifest links and no normalization link; or
2. normalized: predicate false, exactly one same-signal normalization item, VERIFIED normalization review and active VERIFIED method, complete matching pins/typed inputs, and exact target ceiling/preference constraint.

Zero or multiple witnesses reject. `UNKNOWN`, null, stale, conflict, unavailable funding-only targets, and extra-row substitution reject. Finalization recomputes every canonical payload/hash under locks and compares it to persisted pins and candidate input fingerprint. It validates provenance only and never derives assessment/direction or rewrites amounts.

## 7. Compatibility and upgrade

Completed legacy evaluations remain byte-for-byte unchanged and readable. BUILDING legacy rows are classified only by `financial_contract_version IS NULL`:

- no Fit child rows and no candidate fingerprint: authorized assembly may atomically opt in by setting v014;
- any Financial manifest/normalization/signal row or candidate fingerprint: migration preflight aborts with `55000`, count and evaluation IDs; operator must discard/rebuild through existing authorized lifecycle;
- COMPLETED: never backfilled, reopened, or fingerprinted.

Object-phase preflight runs immediately after adding the discriminator, before all other objects, and the entire object phase is transactionally all-or-nothing. Clean `001 -> 014` and populated `013 -> 014` are mandatory. 015 remains unexecuted and absent from every 014 diff/test command.

## 8. Authorization, RLS, ownership, and locks

All new tables are owned by `foundation_evaluation_executor`, RLS enabled and forced. Revoke all privileges from `PUBLIC`, `anon`, `authenticated`, `service_role`.

| object/action | catalog executor | evaluation executor | service role / other roles |
|---|---|---|---|
| review verify/retire entry points | EXECUTE | none | none |
| v014 adopt/pin/typed-insert entry points | none | none | service_role EXECUTE only |
| review table | SELECT only | SELECT/INSERT/UPDATE as definer owner | no direct privilege |
| typed inputs/factors | SELECT | SELECT/INSERT as definer owner while BUILDING+DRAFT | no direct privilege |
| private pins | none | SELECT/INSERT/UPDATE as definer owner only | no direct privilege |
| source registry/cost/evidence tables | SELECT; existing writes unchanged | SELECT + UPDATE privilege solely for row locking | unchanged |

For each locked public source table, retain/add a SELECT policy `USING (true)` for evaluation executor and an UPDATE policy `USING (current_user='foundation_evaluation_executor') WITH CHECK (false)`. The executor receives table UPDATE privilege solely because PostgreSQL requires it for `FOR UPDATE`; `WITH CHECK(false)`, existing immutable/update guards, and no direct UPDATE entry point prevent business mutation. Tests must prove `SELECT ... FOR UPDATE` succeeds and `UPDATE` fails.

All definer functions, including verify/retire wrappers, are owned by `foundation_evaluation_executor`. Verify/retire EXECUTE is granted only to `foundation_catalog_executor`. `adopt_fit_financial_contract_v014`, `pin_fit_financial_source_v014`, and new function-mediated typed input/factor inserts are granted only to `service_role`, matching the frozen Fit assembly API; each requires the existing durable assembly authorization and BUILDING/unsealed state. Every function is `SECURITY DEFINER`, has `SET search_path = pg_catalog, public, private, extensions`, and schema-qualifies every object. Revoke EXECUTE from PUBLIC, `anon`, `authenticated`, `service_role`, and all executor roles before the exact grants. Helpers have no external EXECUTE grant. No role receives CREATE on public/private/extensions and catalog executor receives no direct review-table UPDATE privilege.

Global lock order, used by insert, verify, seal, fingerprint verification, and finalize:

```text
fit_evaluations
-> fit_evaluation_methods / intent set and declarations
-> program_costs
-> canonical_field_selections (amount, then basis by field_name)
-> field_observations (UUID order)
-> applicability heads/assertions (UUID order)
-> evidence_items (UUID order)
-> normalization method
-> financial normalization
-> review
-> typed inputs/factors (ordinal order)
-> manifest items / signal evidence (UUID order)
-> private pins
```

Concurrent authority replacement, retirement, verification, seal, and finalize tests must prove either serialization or fail-closed rejection, never mixed snapshots or deadlock.

## 9. Adversarial executable tests

Every reject asserts SQLSTATE/hint, evaluation remains BUILDING, and no completion fingerprints are written.

1. All five enum labels plus SQL null; exact four mappings; future-label exhaustiveness fails closed.
2. Exhaustive 4 x 6 source/target periods; independent and combined currency/scope/basis/component mismatches.
3. Component reorder equality; null/empty/duplicate/missing/extra rejection; amount changes do not change predicate truth.
4. Separate amount and basis selections succeed; missing/wrong-record/wrong-field/non-KNOWN/stale/conflict/UNKNOWN/null/mismatched-live/retired/non-applicable basis rejects.
5. Basis and amount observations/evidence/applicability must both be manifested and linked to the same signal; cross-signal and extra-row substitution reject.
6. DRAFT normalization cannot finalize; direct VERIFIED insertion rejects; only DRAFT->VERIFIED->RETIRED; reverse/skip/mutation-after-verify rejects.
7. Wrong release/method/version/contract/verification evidence/source/target/profile/evaluation/intent set/constraint rejects.
8. Typed roles/factors: every required role/factor positive; missing, extra, duplicate ordinal/role, wrong type/unit/operation/evidence/value/formula/rounding rejects; arbitrary legacy JSON never supplies authority.
9. `AVAILABLE_FUNDING` alone never acts as ceiling or direct target; gross path forbids it; net path requires exact separate funding declaration and target basis `NET_OF_VERIFIED_FUNDING`; missing/extra/mismatched funding rejects.
10. Each of TOTAL_PROGRAM, PER_YEAR, PER_SEMESTER, PER_CREDIT succeeds directly on exact axes and through one verified normalization for each mismatch class.
11. Persisted discriminator: legacy null remains v011; authorized fresh assembly sets v014; direct/manual/late mutation rejects; no date/fingerprint inference.
12. Two independently generated normalization/source-pin/manifest/input/factor UUID graphs referencing the same authoritative observation/evidence/constraint/method identities and identical semantics produce identical input fingerprints; semantic mutation changes it; duplicate semantic normalization rejects.
13. Mutate each source, selection, applicability, evidence, cost, method, review, factor/input, constraint, manifest link, and pin before seal/finalize; recomputation rejects.
14. Zero/multiple direct or normalized witnesses reject; a valid unrelated normalization cannot satisfy a signal.
15. Supporting and contradicting evaluator outputs with identical admissible provenance are both accepted; SQL never computes direction, assessment, ceiling comparison, or target amount.
16. Executor can row-lock but cannot update every authority table; all owner/grant/RLS/search-path/EXECUTE assertions pass.
17. Concurrency races for selection replacement, evidence/method/normalization retirement, verification, sealing, and finalization serialize or reject without deadlock.
18. Clean and populated upgrades; incomplete legacy preflight failure is atomic and actionable; retry after authorized rebuild succeeds.
19. Full SQL suites `001`–`005`, Eligibility v0.1 `8/8`, v0.2 `12/12`, parity/generator/drift checks pass from the beginning after the last fix.
20. Hash/diff audit proves 001–013 unchanged and 015 unmodified/unexecuted/unabsorbed.

## 10. Freeze and change control

Implementation is authorized only after a final review finds that every DDL column, constraint, state transition, serializer field, authorization, lock, failure mode, compatibility branch, and runner behavior above is mechanical. Any defect receives the smallest additive 014 fix followed by the complete relevant gate rerun. Adjacent semantic, authorization, replay, lifecycle, and fingerprint logic is proactively audited before freeze; a discovered 015-class concern is reported separately and never silently absorbed.

This document does not authorize creating 014 SQL, changing 001–013, executing/modifying 015, or starting Fit Engine.

**MIGRATION 014 PLAN READY FOR FINAL REVIEW**
