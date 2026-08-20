# Phase 2 Student Eligibility

Phase 2 adds student facts, reviewed mappings, verified requirement
interpretations, and deterministic eligibility evaluation without changing
Phase 1 migrations `001`–`003`. The v0.1 contract is frozen; see
[PHASE_2_FREEZE.md](PHASE_2_FREEZE.md) for the authoritative freeze record and
post-freeze change policy.

## Authority boundaries

- Phase 1 canonical columns and selected observations remain authoritative for
  program facts.
- Student raw records and private evidence remain authoritative for student
  facts.
- Taxonomy mappings are authoritative only while their normative status is
  `VERIFIED`. Confidence is proposal workflow metadata and is never an
  eligibility threshold.
- Rule nodes reference selected observations and reviewed mappings. They do not
  persist copied course names, thresholds, or other canonical values.
- The TypeScript library receives resolved DTOs and has no persistence,
  network, environment, SQL, aliases, or embedded program facts.
- Generic student derived features are excluded from the eligibility v0.1 DTO.

## Taxonomy and student snapshots

`taxonomy_concepts.canonical_key` is stable semantic identity across releases.
A meaning change requires retirement and a new key. Labels and aliases may
change without changing identity.

Student accounts are separated from anonymous analytical IDs. A profile
version is writable only while `DRAFT`; freezing requires an explicit
completeness state for every required global domain and for the course history
and mapping coverage of every education context, plus a snapshot hash. Child
facts, evidence, and mappings are immutable after freeze.

Absence is not failure unless the corresponding student history is explicitly
`COMPLETE`. Course predicates require both `COURSE_HISTORY` and
`COURSE_MAPPING` to be complete for every declared education context before no
reviewed match can become `NOT_SATISFIED`. Completeness from an exchange or
other education context never covers another institution. Missing, `PARTIAL`,
or `UNKNOWN` coverage produces `UNKNOWN`.

## Rule verification

The only v0.1 predicates are `HAS_COURSE_CONCEPT` and `HAS_TEST`. The controlled
verification function rejects a rule set unless:

- it has exactly one connected, acyclic root tree;
- every group has children and valid `AT_LEAST(k)` cardinality;
- predicate shapes and taxonomy kinds match the v0.1 engine contract;
- every predicate references a currently selected `KNOWN` observation for the
  same program version;
- course predicates reference an active `VERIFIED` catalog mapping for the same
  program version;
- explicit conditional predicates are direct children of an `ALL` group.

Verified and retired trees are immutable. Obsolete interpretations are retired
instead of overwritten.

## Three-valued semantics

Leaves emit only `SATISFIED`, `NOT_SATISFIED`, or `UNKNOWN`.

- `ANY`: any satisfied child wins; otherwise any unknown child yields unknown;
  otherwise not satisfied.
- `ALL`: any not-satisfied child wins; otherwise any unknown child yields
  unknown; otherwise satisfied.
- `AT_LEAST(k)`: with `s` satisfied and `u` unknown children, satisfied when
  `s >= k`, not satisfied when `s + u < k`, and unknown otherwise.

Soft requirements are explained but do not block eligibility. An explicit
conditional hard gap produces `CONDITIONALLY_ELIGIBLE` only after all ordinary
hard requirements are satisfied. Unknown conditional applicability remains
`UNKNOWN`. The v0.1 evaluator never emits `NOT_APPLICABLE`.

## Replay manifest and results

An evaluation starts in `BUILDING`. Normalized manifest tables pin the exact:

- degree, course, and test rows supplied;
- reviewed student mappings and completeness rows supplied;
- private student evidence references supplied;
- selected catalog observations and reviewed catalog mappings used;
- taxonomy concepts used.

The database requires catalog source/mapping sets to exactly match the verified
rule set and requires a typed match row for every satisfied course or test
predicate. Finalization requires one result per rule node and derives a SHA-256
fingerprint from sorted manifest IDs plus the pinned profile, rule set,
taxonomy, and evaluator versions. Completed manifests and rule-level results
are immutable.

Fingerprint canonicalization is order-independent: inserting the same manifest
associations in a different order produces the same fingerprint. Replacing one
course or mapping ID with another produces a different fingerprint even when
both mappings resolve to the same taxonomy concept.

Replay is guaranteed only while student-owned data exists. Controlled privacy
deletion removes identity links, raw facts, evidence, mappings, derived
features, manifests, and evaluations. It retains only a non-PII tombstone with
deletion time and reason; catalog history remains durable.

## Deferred scope

Phase 2 does not include minimum-score or minimum-grade comparators, arbitrary
conditions or waivers, fuzzy matching, fit or competitiveness scoring,
admission probabilities, rankings, recommendations, API services, or UI.
Unsupported requirement semantics remain `UNKNOWN` until a new reviewed rule
schema and engine contract are introduced.
