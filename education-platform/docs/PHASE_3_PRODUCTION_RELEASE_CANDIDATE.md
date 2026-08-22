# Phase 3 Fit v0.1 production release candidate

Status: **REMOTE RELEASE VERIFIED — PROMOTED TO FINAL PHASE 3 FREEZE**

Date: 2026-08-22

## Scope

This record covers the pure categorical Fit Engine v0.1, its controlled
PostgREST persistence adapter, evaluator-build registration, bounded source
snapshot functions, the authenticated `fit-evaluate` Edge endpoint, and the
separate Financial normalization prepare/review/resume endpoints.

The release candidate preserves the frozen semantic boundary: it produces six
categorical Fit dimensions with separate confidence and evidence coverage. It
does not compute or expose a score, weight, ranking, probability,
recommendation, Eligibility interpretation, or Competitiveness result.

The future Competitiveness modeling direction in `PRODUCT_ARCHITECTURE.md` is
research guidance only. Statistical feature effects belong to a future,
separately approved Competitiveness model and do not change Fit v0.1.

## Release identities

- Fit Engine package: `@education-platform/fit-engine` version `0.1.0`
- Fit Engine source hash:
  `e32a3ed849633a216e84dd23afae5bd60f261333c55e4c5a3c0841f6b795564e`
- Migration 016 hash:
  `fe2c25c4a582fa2c3e3a212224290c3e6d5226765ee32aa0244b9eef98f71ccd`
- Migration 017 hash:
  `71dafe1fa78480072d583c5838b1ddc5e6e0d1e86f3d1c5414c1aca303106670`
- Migration 018 hash:
  `27fd0060e1e4f4133c6a8a86557bff0f38516b07ec218df9a404cbcb775898a0`
- Migration 018 SQL test hash:
  `34b1aacbc778b8ebca3d4f0bd3bda54e409429d8e1cd7f28c6985d0e3a935f52`
- Edge runtime bundle hash:
  `0c6344b98b93ea38282236ac437bd8bc71eec3804bc103d7b09ad6ef790fd5b1`
- Deployed Edge function artifacts (version 1, JWT verification enabled):
  - `fit-evaluate`: `70032212a008aa881dfceed8281b90aed4c835d6192c71a20a59180be62fb65b`
  - `fit-normalization-prepare`: `a99897b15e5850e597182208dfb088147555e1322207c66d11ac07e06bd98ffd`
  - `fit-normalization-review`: `b9d5b31217ed5f9998a094f9421a37f695820703d0beaaa2fcbeebc0fcc3c5c3`
  - `fit-normalization-resume`: `223cf69563a35b2832a7b4f2b23ba8c00f7c28e2b1daef3c7aa77b9be581895a`

Current frozen migration hashes, including the authorized 012/013/015
installer compatibility amendments, are:

- Migration 012 (authorized PG16+ installer compatibility amendment):
  `e4dc07717c3cb2e0d809c9ce5224d43f40639ed03ca9999638b87843f5a839f7`
- Migration 013:
  `65f231e376246191f54a6f8e5a7b8d01810746b3c47e7ecef22f93f84d4a0f58`
- Migration 014:
  `3828faf3f0d3b776575474cf2dc8f70dbedc134eef00baac5d3364dcbf028b53`
- Migration 015:
  `f28572ee2a1b49fbf20b440625bbd73dd9796f650e37588b3d39b49c33acd607`

## Verified gates

- Pure Fit Engine: 14 tests passed.
- Production adapter: 8 tests passed.
- Eligibility v0.1: 8 tests passed.
- Eligibility v0.1/v0.2: 12 combined tests passed; the generated 190-vector parity corpus is
  current.
- Staged PostgreSQL regression: migrations `001`–`013` with tests `001`–`005`,
  then `014`/test `006`, `015`/test `007`, `016`/test `008`, and `017`/test
  `009` passed.
- Actual local Supabase runner: a disposable clean stack discovered and applied
  migrations `001`–`017`; tests `008` and `009` passed on that stack.
- PostgreSQL 15.19 and PostgreSQL 17.11 clean regressions both applied
  migrations `001`–`017` and passed the ordered SQL suites `001`–`009`.
- A separate PostgreSQL 17 non-superuser `CREATEROLE` probe applied the amended
  012 and 013 install paths and mechanically retained effective executor
  `ADMIN`, `INHERIT`, and `SET` capabilities.
- A clean PostgreSQL 17 hosted-default-ACL simulation applied migrations
  `001`–`017` and passed SQL suites `001`–`009`. Final `authenticated`
  execution contained exactly the two ownership helpers plus the intentional
  v017 independent-review RPC, with zero unexpected functions; the simulated
  platform default ACL remained present and unchanged.
- PostgreSQL 15.19 and 17.11 dual-role-stack regressions applied `001`–`015`
  with a temporary `session_user` and a distinct database-owning installer
  `current_user`; Migration 015 restored the installer after its executor-only
  adoption update and revoked temporary executor schema `CREATE` before commit.
- After the authorized 015 hosted-runner amendment, clean PostgreSQL 15.19 and
  17.11 regressions again applied `001`–`017` and passed ordered SQL suites
  `001`–`009`.
- Clean PostgreSQL 15.19 and 17.11 regressions applied `001`–`018` and passed
  ordered SQL suites `001`–`010`. Migration 018 removed external EXECUTE from
  exactly 13 v014 private functions while retaining evaluator-owner access.
- The PostgreSQL 17 hosted-default-ACL regression preserved the platform ACL
  byte-for-byte and reduced the final `authenticated` function set to exactly
  the two ownership helpers plus the intentional v017 reviewer RPC.
- Remote Migration 018 audit passed with one history row, zero forbidden grants
  across the 13 target functions and seven external roles, 13 retained owner
  grants, exactly three authenticated functions, and the hosted platform
  default ACL still present.
- All four Edge Functions are remotely ACTIVE at version 1 with JWT
  verification enabled. Credential-free POST smoke returned HTTP 401 for each
  endpoint, confirming the anonymous gateway boundary.
- API behavior: an authenticated all-UNKNOWN evaluation completed with six
  categorical results and sealed fingerprints.
- Direct Financial behavior: an authenticated evaluation completed with
  Financial `ALIGNMENT / HIGH / SUFFICIENT`, the exact amount-and-billing-basis
  witness, six persisted results, and sealed fingerprints.
- Reviewed Financial behavior: student self-review was rejected; a distinct
  reviewer with the signed reviewer claim verified the artifact; resume reused
  the same `BUILDING` evaluation and completed with exact source,
  normalization, and funding provenance. Gross alignment, gross over-budget
  `MISALIGNMENT`, and net-of-verified-funding alignment paths all passed with
  `MEDIUM / SUFFICIENT`.
- Response-boundary scan confirmed that the API payload contains none of the
  prohibited score, weight, rank, probability, recommendation,
  Competitiveness, or Eligibility semantics.
- Remote authenticated behavior completed both `evaluate` and
  `prepare → independent review → resume`. Student self-review was rejected;
  the reviewer claim was honored; the resumed Financial result was
  `ALIGNMENT / MEDIUM / SUFFICIENT` with sealed fingerprints.
- Smoke cleanup was mechanically verified: both temporary Auth users were
  deleted and confirmed absent, active student/evaluation rows were zero, the
  independent smoke cost was retired, and the golden program version remained
  active.

## Execution-contract evidence

The Migration 014 single-file dual-transaction contract was tested through two
real runner paths with a disposable probe that placed the enum work in the
first transaction and dependent objects in the second:

1. PostgreSQL 15 `psql -v ON_ERROR_STOP=1 -f <probe.sql>`: supported.
2. Supabase CLI `2.115.0` local migration discovery during `supabase start`:
   supported.
3. The linked Supabase migration runner applied the production Migration 014
   file as part of remote history `001`–`018`: supported.

The disposable minimal probe was confined to local runners; the remote result
comes from applying the actual production migration, not from deploying a
probe migration to the project.

## Remote release closure

### Remote deployment

The repository is authenticated and linked to project
`lmcqotzbaoetnxceriwq`. Remote migration history contains `001`–`018`;
Migration 015's objects were mechanically verified after its explicit commit
and its missing history row was repaired before 016–017 were applied.

All four Edge Functions are deployed and ACTIVE with JWT verification enabled.
The authenticated end-to-end behavior smoke passed. The anon/service-role keys
were read only inside one ephemeral process and were not printed or written to
files. Two disposable confirmed Auth users were created, used, deleted, and
confirmed absent. The smoke used and retired a separately identified cost row
under the unchanged golden program version; it did not mutate the golden
UNKNOWN cost record.

## Freeze decision

Migration `016` and the API passed local and remote release verification.
Migration `017` closes the independently reviewed Financial
normalization/resume gate, and Migration `018` closes the remote private-
function ACL blocker without semantic changes. Authenticated reviewer
provisioning, end-to-end remote behavior, and cleanup are now mechanically
verified. The authoritative final decision is recorded in
[`PHASE_3_FREEZE.md`](PHASE_3_FREEZE.md): **PHASE 3 FIT v0.1 FROZEN**.
