# Phase 3 Fit v0.1 — FROZEN

Status: **FINAL PHASE 3 FREEZE APPROVED**

Date: 2026-08-22

## 1. Freeze scope

This record freezes the production Fit v0.1 release composed of:

- the six-dimension categorical Fit contract and persistence layer in
  migrations `009`–`011`;
- Foundation, Eligibility, Financial billing-basis, and replay/seal hardening
  through migrations `012`–`015` under their existing freeze records;
- the pure Fit Engine v0.1 and controlled persistence adapter;
- the verified evaluator-build registration in Migration `016`;
- the independently reviewed Financial normalization workflow in Migration
  `017`;
- the least-privilege v014 private-function ACL correction in Migration `018`;
- the four authenticated Edge Functions: `fit-evaluate`,
  `fit-normalization-prepare`, `fit-normalization-review`, and
  `fit-normalization-resume`.

The release produces exactly six categorical Fit dimensions with separate
confidence and evidence coverage. It does not compute or expose scores,
weights, rankings, probabilities, recommendations, Eligibility
reinterpretation, or Competitiveness.

The future Competitiveness modeling direction in `PRODUCT_ARCHITECTURE.md` is
an architecture note only. It neither changes this release nor authorizes an
implementation.

## 2. Release identities

- Fit Engine package: `@education-platform/fit-engine` version `0.1.0`
- Fit Engine source hash:
  `e32a3ed849633a216e84dd23afae5bd60f261333c55e4c5a3c0841f6b795564e`
- Edge runtime bundle hash:
  `0c6344b98b93ea38282236ac437bd8bc71eec3804bc103d7b09ad6ef790fd5b1`
- Migration 012:
  `e4dc07717c3cb2e0d809c9ce5224d43f40639ed03ca9999638b87843f5a839f7`
- Migration 013:
  `65f231e376246191f54a6f8e5a7b8d01810746b3c47e7ecef22f93f84d4a0f58`
- Migration 014:
  `3828faf3f0d3b776575474cf2dc8f70dbedc134eef00baac5d3364dcbf028b53`
- Migration 015:
  `f28572ee2a1b49fbf20b440625bbd73dd9796f650e37588b3d39b49c33acd607`
- Migration 016:
  `fe2c25c4a582fa2c3e3a212224290c3e6d5226765ee32aa0244b9eef98f71ccd`
- Migration 017:
  `71dafe1fa78480072d583c5838b1ddc5e6e0d1e86f3d1c5414c1aca303106670`
- Migration 018:
  `27fd0060e1e4f4133c6a8a86557bff0f38516b07ec218df9a404cbcb775898a0`
- Migration 018 SQL test:
  `34b1aacbc778b8ebca3d4f0bd3bda54e409429d8e1cd7f28c6985d0e3a935f52`

Deployed Edge artifacts are version 1 with JWT verification enabled:

- `fit-evaluate`:
  `70032212a008aa881dfceed8281b90aed4c835d6192c71a20a59180be62fb65b`
- `fit-normalization-prepare`:
  `a99897b15e5850e597182208dfb088147555e1322207c66d11ac07e06bd98ffd`
- `fit-normalization-review`:
  `b9d5b31217ed5f9998a094f9421a37f695820703d0beaaa2fcbeebc0fcc3c5c3`
- `fit-normalization-resume`:
  `223cf69563a35b2832a7b4f2b23ba8c00f7c28e2b1daef3c7aa77b9be581895a`

## 3. Accepted verification gates

- Clean PostgreSQL 15.19 and 17.11 regressions applied migrations `001`–`018`
  and passed ordered SQL suites `001`–`010`.
- The real local Supabase migration runner accepted the Migration 014
  single-file dual-transaction contract.
- Hosted PostgreSQL role-stack and default-ACL regressions passed without
  changing platform default ACL behavior.
- Migration 018 retained evaluator-owner execution on all 13 target functions,
  removed every forbidden external grant, and left exactly the three intended
  authenticated functions.
- Fit Engine: 14/14 tests passed.
- Fit persistence adapter: 8/8 tests passed.
- Eligibility v0.1/v0.2: 12/12 combined tests passed; the v0.2 generated
  registry check is current.
- Remote project `lmcqotzbaoetnxceriwq` contains migration history `001`–`018`.
- All four Edge Functions are ACTIVE with JWT verification enabled; anonymous
  POST requests were rejected with HTTP 401.
- The authenticated remote smoke completed both `evaluate` and
  `prepare → independent review → resume`. Student self-review was rejected,
  the reviewer claim was honored, and resumed Financial output was
  `ALIGNMENT / MEDIUM / SUFFICIENT` with sealed input/result fingerprints.
- The response-boundary scan found none of the prohibited score, weight, rank,
  probability, recommendation, Competitiveness, or Eligibility semantics.

## 4. Remote smoke cleanup proof

The authorized remote smoke read the anon and service-role keys only inside one
ephemeral process. Keys, access tokens, user passwords, and temporary user
identifiers were neither printed nor written to files.

After verification:

- both temporary Auth users were deleted and individually confirmed absent;
- the temporary student and active evaluation rows were deleted and confirmed
  at zero;
- the independently identified smoke `PROGRAM_COST` was retired;
- the existing golden program version remained active and was not rewritten.

Immutable catalog evidence attached to the retired smoke record remains as
historical provenance by design. The privacy deletion tombstone, if retained
by the deletion contract, is not active student or evaluation data.

## 5. Frozen semantic boundaries

- Eligibility remains rule logic and is never learned from admission outcomes.
- Fit remains categorical preference/constraint interpretation with no learned
  weights or composite score.
- Financial `AVAILABLE_FUNDING` remains distinct from a cost ceiling.
- Financial normalization remains exact-decimal, same-currency, versioned,
  independently reviewed, and fail-closed.
- Completed evaluation replay uses frozen pins and fingerprints rather than
  post-seal live reads.
- Unknown, stale, conflicting, inapplicable, or incomplete evidence never
  becomes an inferred positive fact.

## 6. Post-freeze change policy

Migrations `001`–`018`, the registered evaluator identity, and the deployed
v0.1 semantic behavior are frozen. Future changes require the smallest
additive migration and, when behavior changes, a new evaluator/model version
with new review and regression evidence. Existing migration bytes must not be
edited without an explicit emergency compatibility authorization and an
updated freeze record.

Competitiveness, outcome learning, ranking, recommendation, probability, UI,
monitoring, and new normalization/conversion methods remain separate future
work. This freeze does not authorize them.

## 7. Freeze decision

All defined local, runner, permission, deployment, anonymous-authentication,
authenticated behavior, independent-review, replay/fingerprint, and cleanup
gates are closed.

**PHASE 3 FIT v0.1 FROZEN — PRODUCTION RELEASE VERIFIED.**

This is a documentation-and-hash freeze consistent with prior project freeze
records. No Git commit or tag is created by this record.
