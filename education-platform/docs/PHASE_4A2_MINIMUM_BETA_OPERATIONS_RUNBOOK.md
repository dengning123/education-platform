# Phase 4A-2 Minimum Beta Operations Runbook

Status: **LOCAL GATES AND MANUAL REMOTE READ-ONLY DRY RUN PASSED — PRIVATE
BETA REMAINS BLOCKED UNTIL ALL BLOCKERS IN SECTION 8 ARE CLOSED**

Frozen application baseline:
`d204f649f87302d225726f7278d5d23c51d3edc1`, annotated tag
`phase4a1-edge-http-v1-final`.

This runbook adds no application runtime, database schema, migration,
deployment, scheduled job, alert, dashboard, telemetry store, or synthetic
traffic. It is a manual operating procedure for a 5–20 person private beta.

## 1. Authorized assets

- `scripts/phase4a2-minimum-beta-ops.mjs` is the manual aggregate-only
  operational checker.
- `supabase/snippets/phase4a2_minimum_beta_invariants.sql` is the count-only
  database invariant pack.
- `scripts/phase4a2-minimum-beta-ops.test.mjs` and
  `scripts/phase4a2-minimum-beta-sql.test.mjs` are pure local tests.

The checker calls only these Supabase Management API paths:

- `GET /v1/projects/{ref}/functions`;
- `GET /v1/projects/{ref}/analytics/endpoints/logs`;
- `GET /v1/projects` to resolve the organization without emitting project
  metadata;
- `GET /v1/organizations/{slug}/members`, reading only `role_name` and
  `mfa_enabled` and emitting counts/status only;
- optional `POST /v1/projects/{ref}/database/query/read-only`, which executes
  the extracted count query as `supabase_read_only_user`.

The POST method on the last path is a read-only query transport. It is not a
database write path. The source SQL pack also begins with `BEGIN READ ONLY`
and ends with `ROLLBACK` for direct `psql -f` use.

## 2. Privacy and credential contract

The checker never emits or groups by:

- student, profile, evaluation, normalization, evidence, execution, request,
  deployment, function, Auth-user, or session identifiers;
- name, email, IP address, geographic/network attribute, header, JWT value,
  cookie, request/response body, free text, evidence content, database error
  text, Fit/Eligibility result, or financial value;
- raw `event_message`, `log_attributes`, database rows, SQL error details, or
  Management API error bodies.

Permitted outputs are fixed endpoint/release/status/error dimensions,
deployment name/status/version/JWT-verification metadata, MFA owner counts,
and fixed database check codes with violation counts.

The access token is accepted only through the process environment and is
deleted from the child process environment immediately after startup. It must
come from the official Supabase CLI keyring or another approved transient
secret source. Never place it in a command argument, repository file, shell
history, log, screenshot, or output. The checker does not accept an anon or
service-role key.

## 3. Local verification

From `education-platform`:

```bash
node --test \
  scripts/phase4a2-minimum-beta-ops.test.mjs \
  scripts/phase4a2-minimum-beta-sql.test.mjs
```

The tests use mocked HTTP responses only. They send no network request and
write no database or Supabase state.

## 4. Manual checker execution

Run only from a controlled terminal after loading a personal Management API
token into `SUPABASE_ACCESS_TOKEN` without echo or persistence:

```bash
node scripts/phase4a2-minimum-beta-ops.mjs \
  --project-ref lmcqotzbaoetnxceriwq \
  --include-database
```

The default window is the most recent 1,440 minutes. `--window-minutes` accepts
only `1..1440`. For a five-minute incident check, rerun with
`--window-minutes 5`.

Do not pass `--owner-configured` or `--notification-channel-configured` until
the corresponding out-of-repository entries in section 7 exist and have been
verified. Those flags contain booleans only; owner/channel names must never
enter checker output.

## 5. Required checks after every internal E2E

Immediately after an authorized internal E2E run:

1. Read back all four function metadata entries. Require ACTIVE, version 9,
   and `verify_jwt=true`.
2. Require every `FIT_EDGE_REQUEST_V2` event to have the exact frozen semantic
   release, deployed build, boundary version, 12-field contract, status class,
   closed error code, UUID-shaped request ID count, and bounded duration.
3. Review aggregate 5xx, deadline, boundary 403, gateway 401, and gateway 403
   counts. Do not inspect raw gateway attributes.
4. Require both completed fingerprint invariant counts and the verified
   Financial graph invariant count to equal zero.
5. Require Fit and Eligibility stale `BUILDING >15m` counts to equal zero.
6. Review, but do not automatically page on, Financial `DRAFT >72h`.
7. Execute the separately authorized complete privacy-deletion table-inventory
   test before external beta. This runbook does not authorize that synthetic
   test or any deletion request.

## 6. Private-beta operating cadence and pause rules

During a private beta, run the checker at least twice each calendar day while
users are active, after every deployment/configuration change, and immediately
after any supported client reports an internal failure.

Pause new beta activity immediately when any of the following occurs:

- a function is missing, inactive, not version 9, or has unexpected JWT
  verification;
- any semantic release, deployed build, boundary version, event field, status
  class, or error code is outside the frozen catalog;
- either completed fingerprint invariant or the verified Financial graph
  invariant is non-zero;
- Fit or Eligibility stale `BUILDING >15m` is non-zero and remains non-zero on
  an immediate second check, or grows between checks;
- at least five internal 5xx responses occur in a five-minute checker window;
- three consecutive controlled E2E requests return a closed internal 5xx;
- a deadline failure repeats in two consecutive five-minute checks;
- any privacy-deletion command fails, produces an uncertain result, or cannot
  prove complete table-inventory removal;
- Owner MFA is disabled or unknown;
- there is no assigned operational owner or working manual notification
  channel.

One isolated internal 5xx requires immediate manual review but is not by
itself proof of a sustained service outage. Do not retry privacy deletion or
non-idempotent operations until their state is proven.

Financial `DRAFT >72h` is a reviewer-queue condition. Escalate during working
hours; pause the beta only when it represents a broken review path or prevents
the promised user flow.

## 7. Owner and notification configuration location

The canonical configuration location is an access-controlled, encrypted
private operations register outside Git:

`education-platform / minimum-beta-operations`

It must contain:

- one primary operational owner and one backup;
- one manual notification channel and a tested contact procedure;
- the beta pause authority;
- the last successful checker timestamp and reviewer;
- confirmation that every Owner account has MFA enabled.

Current repository state intentionally contains no owner name, email, phone,
chat identifier, token, or notification URL. Until the private register is
populated and tested, both configuration items remain private-beta blockers.

## 8. Known blockers that this scope cannot close

1. The current schema/event set has no truthful privacy-deletion attempt or
   integrity-failure signal. The deletion transaction is atomic and the
   tombstone is intentionally non-linkable, but neither records failed
   attempts. A future privacy-safe command signal and a complete deletion E2E
   require separate authorization.
2. Owner MFA must be enabled through the account security UI by an authorized
   human. This checker may only report its aggregate status.
3. The operational owner and manual notification channel must be assigned in
   the private register. They are deliberately not stored in Git.

These blockers do not prevent Phase 4B-1 development or controlled internal
E2E. They do prevent external private beta.

## 9. Explicitly deferred

The minimum beta does not require a dashboard, scheduled reader, automated
alert, monitoring vendor, Metrics endpoint, durable aggregate store, log
drain, seven-day baseline, warm p95 baseline, or generalized tracing. The
Free-plan one-day native log window is accepted only with the twice-daily
manual cadence above. These items must be reconsidered before public or larger
beta rollout.

## 10. Stop boundary

Running this procedure never authorizes Phase 4B-1, Migration 019,
Competitiveness, a deployment, a migration, a database mutation, synthetic
traffic, or a change to the frozen Phase 4A-1 four-function compatibility set.

## 11. Executed manual read-only dry run

One authorized remote dry run was executed on 2026-08-22 over the most recent
1,440-minute native log window. It used the Supabase CLI keyring only in
process memory, the aggregate Logs endpoint, function metadata GET paths, and
the Management API database read-only endpoint. It sent no Edge request and
created or modified no Auth, application, database, deployment, or
configuration state.

Sanitized results:

- all four functions were ACTIVE at version 9 with `verify_jwt=true`;
- 40/40 `FIT_EDGE_REQUEST_V2` events satisfied the exact field, release,
  build, boundary, status, error-code, request-ID-shape count, and duration
  contract;
- release-identity mismatch count was zero;
- internal 5xx and deadline-failure counts were zero;
- boundary 403 count was 8, gateway 401 count was 85, and gateway 403 count
  was 16; these are aggregate historical smoke-window counts, not a natural
  beta baseline;
- all six database count-only invariants returned zero violations;
- exactly one Owner was visible to the aggregate MFA check and that Owner had
  MFA disabled.

The checker therefore returned `PRIVATE_BETA_BLOCKED` with four blockers:

- `OWNER_MFA_NOT_ENABLED`;
- `OPERATIONAL_OWNER_UNASSIGNED`;
- `MANUAL_NOTIFICATION_CHANNEL_UNASSIGNED`;
- `PRIVACY_DELETION_INTEGRITY_SIGNAL_UNAVAILABLE`.

No raw log row, member identity, user-linked identifier, database row, error
detail, financial value, or Fit/Eligibility result was emitted or persisted.
