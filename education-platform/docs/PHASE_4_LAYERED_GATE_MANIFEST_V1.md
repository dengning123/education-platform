# Phase 4 Layered Gate Manifest v1

Status: local tooling only; not a baseline commit, release, deployment, or CI
workflow.

## Purpose

The layered gate runner reduces repeated proof during bounded implementation
work without weakening final proof. It exposes exactly four closed gates:

- `FAST`: quick targeted feedback;
- `RELEVANT`: the real executable path for the currently reviewed bounded
  increment;
- `BASELINE`: the complete local proof required before commit/push;
- `RELEASE`: the complete `BASELINE` followed by remote/deployment
  preconditions.

`FAST` and `RELEVANT` are intermediate feedback tools. They never authorize a
commit, push, deployment, remote mutation, migration-history repair, or a claim
that final regressions are unnecessary.

## Files and command line

- `scripts/phase4-layered-gates.manifest.json` is the closed manifest.
- `scripts/phase4-layered-gates.catalog.mjs` is the audited command catalog and
  immutable minimum-strength policy.
- `scripts/phase4-layered-gates.mjs` validates, explains, preflights, times, and
  executes catalog identities without a shell.
- `scripts/phase4-layered-gates.test.mjs` is the pure-local security and
  behavior suite.

Run with a Node.js 20+ executable:

```text
node scripts/phase4-layered-gates.mjs validate
node scripts/phase4-layered-gates.mjs dry-run FAST
node scripts/phase4-layered-gates.mjs explain RELEVANT
node scripts/phase4-layered-gates.mjs preflight BASELINE
node scripts/phase4-layered-gates.mjs run FAST
```

Gate names are exact and case-sensitive. Unknown modes, gates, extra arguments,
command identities, manifest keys, catalog references, or paths outside the
repository fail closed. There is no free-form command argument and every child
process uses `shell: false`.

## Closed manifest schema

The top-level object contains exactly:

```text
schemaVersion
policy
gates
```

The policy fixes:

- fail-fast execution;
- no shell execution;
- no changed-path skipping for `BASELINE`;
- no changed-path skipping for `RELEASE`;
- 1 GiB minimum free disk for light work;
- 8 GiB minimum free disk for heavy work.

Each gate declares a bounded description, light/heavy classification,
prerequisites, and an ordered list of `{ id, why }` references. `RELEASE` must
also declare `extends: BASELINE`.

The code contains an exact minimum command order for all four gates. A manifest
cannot delete, reorder, replace, or configure away a `BASELINE` or `RELEASE`
command. `RELEASE` resolves mechanically to all `BASELINE` commands followed by
its release-only commands, so it is a strict superset.

## FAST

`FAST` is light and does not require Docker, PostgreSQL, Supabase, or a remote
service. Its order is:

1. light read-only disk preflight;
2. layered tooling unit/security tests;
3. targeted M027 Intent/M028 Fit compatibility orchestration and security tests;
4. targeted existing Profile command/DTO/source/semantic/no-AI tests;
5. `git diff --check`.

The Profile package test requires dependencies installed from the committed
lockfile. Failure does not cause fallback to a smaller test.

## RELEVANT

Manifest v1 binds `RELEVANT` to the currently reviewed Migration 029
privacy-deletion compatibility repair over the M027 Intent graph and the M028
product Fit build. It is intentionally conservative:

1. heavy read-only disk/Docker preflight;
2. clean PostgreSQL 17 non-superuser `001→029` runner path;
3. Phase 027 lifecycle/assembly/security/idempotency/privacy SQL;
4. Phase 028 evaluator-build registration/ACL SQL;
5. Phase 029 authorized-cascade/direct-role/spoof/rollback/privacy SQL;
6. populated `027→028` legacy/completed-evaluation preservation proof;
7. populated `028→029` M027 graph preservation and privacy closure proof;
8. Phase 029 deletion-versus-mutate/freeze/evaluation concurrency proof;
9. actual local `supabase db reset --local` path;
10. Phase 027 Auth-issued JWT/PostgREST lifecycle and assembly E2E;
11. frozen Fit Engine categorical regression;
12. product-aware adapter/parser and legacy parity regression;
13. real local Browser → Next → Auth → Edge → PostgREST → PostgreSQL product flow;
14. targeted M027 Intent/M028 Fit command, DTO, and source-boundary tests;
15. product-aware runtime reproducibility;
16. `git diff --check`.

A future bounded increment needs a reviewed manifest version to change this
mapping. The runner never infers relevance from changed paths and accepts no
caller-supplied test file or command.

## BASELINE

`BASELINE` preserves the current complete local final-proof categories:

1. heavy read-only preflight;
2. PostgreSQL 15 non-superuser clean `001→029`;
3. PostgreSQL 17 non-superuser clean `001→029`;
4. version-boundary ordered SQL suites `001–021`;
5. populated `023→024` upgrade;
6. populated `024→025` upgrade;
7. populated `025→026` upgrade;
8. populated `026→027` upgrade;
9. populated `027→028` legacy/completed-evaluation preservation proof;
10. populated `028→029` M027 graph preservation and privacy closure proof;
11. actual local Supabase reset;
12. Phase 024 behavior/security/privacy;
13. Phase 025 discovery/security/privacy;
14. Phase 026 assembly/security/idempotency/privacy;
15. Phase 027 lifecycle/assembly/security/idempotency/privacy;
16. Phase 028 evaluator-build registration/ACL proof;
17. Phase 029 authorized-cascade/direct-role/spoof/rollback/privacy proof;
18. Phase 024 definition concurrency;
19. Phase 020 Profile fork concurrency;
20. Phase 027 lifecycle concurrency;
21. Phase 029 deletion concurrency and no-resurrection proof;
22. Phase 021–025 real local Auth/PostgREST matrix;
23. Phase 026 real local Auth/PostgREST concurrent assembly matrix;
24. exact local Auth restart followed by Phase 026 E2E;
25. Phase 027 real local Auth/PostgREST lifecycle and assembly matrix;
26. exact local Auth restart followed by Phase 027 E2E;
27. Eligibility full suite;
28. Fit Engine full suite;
29. production adapter full suite;
30. frozen Edge HTTP boundary suite;
31. Minimum Beta Operations checker/query-pack tests;
32. Web unit/contract/security suite;
33. full fake browser/auth/Profile/accessibility/mobile suite;
34. real local Browser → Next → Auth → Edge → PostgREST → PostgreSQL lifecycle;
35. targeted M027 Intent/M028 Fit compatibility orchestration contract suite;
36. lint;
37. TypeScript;
38. Next.js production build;
39. client-secret/test-fixture source boundary;
40. semantic/no-AI executable guards;
41. product-aware Fit runtime rebuild/reproducibility;
42. frozen Migration 001–027/semantic/Financial-Edge/fingerprint/runtime audit;
43. final `git diff --check`.

The ordered SQL command applies and tests frozen versions at their documented
boundaries; it does not incorrectly run old negative-leakage tests only after
all later objects exist. Database commands create exact disposable PostgreSQL
containers with tmpfs data and invoke the existing SQL/scripts unchanged.

No changed-path setting can shorten this list. A successful `FAST` or
`RELEVANT` run is not accepted as evidence for a `BASELINE` result.

## RELEASE

`RELEASE` always re-runs the complete `BASELINE`, then adds:

1. read-only linked remote migration-history inspection;
2. the existing aggregate-only Minimum Beta Operations checker, including its
   read-only database query pack;
3. an explicit deployment authorization hold;
4. an explicit hosted smoke authorization hold;
5. an explicit rollback/readiness review hold.

The final three identities are deliberate fail-closed positions. This local
tooling authorization does not permit deployment, hosted smoke traffic, remote
data creation, or a rollback decision. A later, separately authorized release
increment must replace those holds with reviewed, closed commands. They cannot
be bypassed with a CLI flag or changed-path claim.

The remote checker receives `PHASE4_RELEASE_PROJECT_REF` and
`SUPABASE_ACCESS_TOKEN` only through the process environment. The access token
is not placed in display text, timing records, or child-process arguments.

## Read-only preflight

Preflight reads host filesystem availability using the operating system's
filesystem statistics. Heavy preflight also uses only these Docker actions:

```text
version
info
ps
inspect
logs --tail 200
```

It never calls `run`, `exec`, `start`, `stop`, `restart`, `rm`, or `prune`.
Docker logs are scanned in memory for read-only filesystem, I/O, ext4, WAL
fsync, and potential-data-loss markers; raw logs are not emitted. If the exact
local Supabase database container is running, its running/health state is also
checked.

This is a safe observable health signal, not a destructive write/fsync probe.
An unavailable daemon, unreadable health state, unsafe marker, unhealthy local
database, or free disk below the fixed threshold fails the heavy gate before
tests start.

The actual gate commands may create disposable local PostgreSQL containers,
reset the disposable local Supabase database, or restart the exact local Auth
container where the manifest explicitly says so. Those are test commands, not
preflight behavior.

## Dry-run, explain, timing, and failures

`dry-run` and `explain` validate the same closed manifest and references but
execute no preflight, test, Docker, Supabase, or remote command. Both display:

- resolved command identity;
- sanitized command template;
- reason;
- prerequisite;
- deterministic order;
- light/heavy classification.

Every real command produces one bounded timing event with its identity,
classification, duration, status, and original exit code. The gate produces a
total-duration event. Tool-owned events never contain environment variables,
JWTs, API keys, credentials, request/response bodies, or raw Docker logs.

Execution is fail-fast. A required command's nonzero exit code is returned as
the gate exit code; the runner neither converts it to success nor continues to
later commands. Internal runner/configuration failures use closed failure
codes.

## Expected workflow benefit

During implementation, `FAST` avoids Docker/Supabase/browser/full-package
startup and `RELEVANT` avoids unrelated frozen back-end and complete Web proof.
The expensive dual-version replay, full browser/build, reproducibility, and
frozen audits still run once at the baseline boundary and again for release.

The benefit is shorter intermediate feedback and less repeated database/browser
startup. It is not a reduction in final test count or assurance.

## Limitations

- Manifest v1's `RELEVANT` mapping is specific to the current M029 M027-privacy
  compatibility repair over the M028 product Fit build; it is not a general
  changed-path selector.
- Package and Playwright dependencies must be installed before package/browser
  commands run. The runner does not change package versions or lockfiles.
- Required PostgreSQL/Supabase/Docker images must already be available; the
  runner does not prune or optimize Docker state.
- Heavy preflight can observe health and known corruption markers but cannot
  prove storage writes without mutation.
- `RELEASE` intentionally cannot pass its remote-mutation holds under this
  authorization.
- CI, database templates/snapshots, cache reuse, deployment, and remote smoke
  implementation remain outside v1.
