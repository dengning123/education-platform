# Migration 023 Application and Outcome Data Contract Plan

Status: **PLANNING ONLY — NO MIGRATION SQL AUTHORIZED OR CREATED**

Date: 2026-08-22

Reserved migration identity:
`202608230023_application_outcome_contract.sql`

Reserved test identity:
`supabase/tests/015_phase023_application_outcome_contract.sql`

Migration 023 is a provisional future planning number until separate
Application/Outcome implementation authorization. It is not a permanently
reserved slot and no Migration 023 SQL exists.

Frozen upstream baseline: commit
`55296e1aeca9a25b066e9010c376f0e618af59d1`, tag `phase3-fit-v0.1`,
migrations `001`–`018`

## 1. Purpose

Migration 023 will define a privacy-aware, version-pinned record of a real
student application and its reported/reviewed admission outcome. Its purpose
is operational application tracking and trustworthy future data collection.

It does not create a training dataset, feature table, model, weight,
probability, ranking, recommendation, or Competitiveness output. A future model
phase may consume separately approved extracts only after data quality,
consent, bias, calibration, and privacy review.

## 2. Non-negotiable invariants

1. Every submitted application pins one frozen student profile, one frozen Fit
   intent set, one completed Eligibility v0.2 evaluation, one completed Fit
   v0.1 evaluation, and one exact program version.
2. The application snapshot copies the relevant version discriminators and
   fingerprints. Later replay never reconstructs the submission from live
   rows.
3. Eligibility remains a rule outcome; Fit remains categorical preference and
   constraint semantics. Neither becomes an admission-outcome feature by
   implication.
4. Outcomes are immutable observations. Review and current selection are
   separate records.
5. A user may report an outcome but may not independently verify the same
   observation.
6. `UNKNOWN` and `NO_DECISION` are distinct: `UNKNOWN` means the result is not
   known; `NO_DECISION` is a known closed-without-decision state supported by
   evidence/review.
7. `WAITLISTED` is non-terminal and may later be superseded.
8. Application and outcome rows are student-owned, RLS-protected, and deleted
   by the existing student privacy lifecycle.
9. Global audit or telemetry tables may not retain student/application IDs
   after privacy deletion.
10. Research consent never upgrades evidence quality and outcome verification
    never implies research consent.

## 3. Proposed types

Migration 023 creates new types rather than altering frozen enums:

```text
application_lifecycle_state
  DRAFT | CANCELLED | SUBMITTED | WITHDRAWN | DECIDED | CLOSED_NO_DECISION

application_origin
  STUDENT_ENTERED | PLATFORM_ASSISTED

application_outcome_code
  ADMITTED | REJECTED | WAITLISTED | WITHDRAWN | NO_DECISION | UNKNOWN

application_outcome_source_kind
  SELF_REPORT | DECISION_LETTER | SCHOOL_PORTAL | SCHOOL_EMAIL |
  COUNSELOR_ATTESTATION | OTHER

application_outcome_review_decision
  VERIFIED | REJECTED

application_outcome_verification_level
  PLAUSIBILITY_REVIEWED | DOCUMENT_VERIFIED | SOURCE_VERIFIED

application_outcome_review_reason_code
  EVIDENCE_MATCHED | SOURCE_CONFIRMED | INSUFFICIENT_EVIDENCE |
  CONFLICTING_EVIDENCE | INVALID_EVIDENCE

application_research_consent_decision
  GRANTED | WITHDRAWN
```

Codes are closed. No caller-defined outcome, lifecycle, verification, or
consent strings are accepted.

## 4. Proposed table contract

### 4.1 `public.student_applications`

One row represents one actual application to one exact program version.

| Column | Contract |
|---|---|
| `application_id uuid PK` | Generated semantic object identity. |
| `student_id uuid NOT NULL` | FK to `students`, `ON DELETE CASCADE`. |
| `program_version_id uuid NOT NULL` | FK to `program_versions`, `ON DELETE RESTRICT`. |
| `application_round_code text` | Optional normalized uppercase code with a closed format, not free text. |
| `origin application_origin NOT NULL` | Student-entered or platform-assisted only. |
| `lifecycle_state application_lifecycle_state NOT NULL` | Starts `DRAFT`. |
| `submission_snapshot_id uuid` | NULL in DRAFT; points to the sealed submission snapshot afterward. |
| `creation_request_id uuid NOT NULL` | Owner-scoped idempotency key. |
| `cancellation_request_id uuid` | Present only in CANCELLED; owner-scoped idempotency key. |
| `created_at/updated_at` | Operational timestamps, excluded from fingerprints. |
| `submitted_at/closed_at` | State-shape constrained timestamps. |

Required keys and constraints:

- unique `(student_id, application_id)` for child composite FKs;
- unique `(student_id, creation_request_id)`;
- unique `(student_id, cancellation_request_id)` when cancellation request is
  non-NULL;
- unique normalized `(student_id, program_version_id, application_round_code)`
  over non-CANCELLED rows so retries cannot create duplicate active/real
  applications while a cancelled draft does not block a later restart;
- DRAFT has no snapshot/submission/closure time;
- CANCELLED has no snapshot/submission time and has a closure time;
- SUBMITTED has a sealed snapshot and submission time but no closure time;
- WITHDRAWN, DECIDED, and CLOSED_NO_DECISION have a sealed snapshot,
  submission time, and closure time;
- round codes match `^[A-Z][A-Z0-9_]{0,63}$` when present;
- program version and application round code are immutable after submission;
- physical DELETE is forbidden except the authorized privacy cascade.

### 4.2 `public.application_submission_snapshots`

Exactly one immutable row seals the submission-time decision context.

Identity and ownership:

- `application_snapshot_id uuid PK`;
- `application_id`, `student_id`, and `program_version_id`;
- unique `application_id`;
- unique `(application_id, application_snapshot_id)`;
- composite FK `(application_id, student_id)` to the owner application;
- `ON DELETE CASCADE` from the application.

After this table exists, `student_applications` receives a composite FK
`(application_id, submission_snapshot_id)` to
`(application_id, application_snapshot_id)`. This prevents a valid snapshot ID
from another application from satisfying the lifecycle-state check.

Pinned student and decision context:

- `profile_version_id` and copied `profile_snapshot_hash`;
- `intent_set_id` and copied `intent_snapshot_hash`;
- `eligibility_evaluation_id`;
- copied Eligibility input schema, evaluator name/version/build hash,
  input fingerprint, result semantics version, result fingerprint, and
  categorical outcome;
- `fit_evaluation_id`;
- copied Fit contract release, evaluator build ID/name/version/build hash,
  candidate/decision/result fingerprints, and evaluation-as-of time;
- copied program admission-cycle start/end, entry term, and entry year;
- discriminator exactly `APPLICATION_SNAPSHOT_V023`;
- canonical `application_snapshot_fingerprint` as lowercase SHA-256;
- `sealed_at` and `submission_request_id`.

Submission validation must prove inside one transaction and under locks:

- profile and intent are frozen and belong to the application owner;
- Eligibility is `COMPLETED`, uses `eligibility-v0.2`, has valid input/result
  fingerprints, and its rule set belongs to the same program version;
- Fit is `COMPLETED`, uses `fit-v0.1`, belongs to the same profile/intent and
  program version, and has all three valid fingerprints;
- Fit's display-only `eligibility_context_evaluation_id` is either NULL or
  exactly the Eligibility evaluation pinned by this submission; a different
  non-NULL context is rejected even though it is excluded from the Fit
  decision fingerprint;
- copied hashes and discriminators equal the source rows after locks;
- the program version is active at submission;
- no selected object belongs to another student or program.

The canonical fingerprint includes semantic/pinned identities and copied
values listed above plus application ID and normalized round code. It excludes
timestamps, actor identity, request IDs, random snapshot ID, and physical row
order.

### 4.3 `public.application_outcome_observations`

An observation is an append-only report, not the current authoritative
outcome.

| Column | Contract |
|---|---|
| `outcome_observation_id uuid PK` | Immutable observation identity. |
| `application_id`, `student_id` | Composite owner FK, cascade on application deletion. |
| `outcome_code application_outcome_code` | Closed reported value. |
| `source_kind application_outcome_source_kind` | Exact source class. |
| `decision_date date` | Nullable when the exact date is unknown. |
| `evidence_content_hash text` | Optional SHA-256; required for document/portal/email sources. |
| `supersedes_observation_id uuid` | Optional same-application predecessor. |
| `report_request_id uuid` | Owner-scoped idempotency key. |
| `reported_at timestamptz` | Audit time, excluded from semantic comparison. |

No raw document, email, portal content, free-form explanation, URL, or storage
path is stored in this table. Evidence binaries require a separately approved
storage/privacy design. Migration 023 retains only typed metadata and a hash.

`DOCUMENT_VERIFIED` or `SOURCE_VERIFIED` may be written only after the reviewer
has accessed the evidence through a separately approved ephemeral evidence
delivery or direct-source confirmation path. Without that path, v023 permits
only `PLAUSIBILITY_REVIEWED`; a content hash alone is never treated as proof.

Supersession constraints prevent self-supersession, branching from one prior
observation, cross-application supersession, and cycles. Update/delete is
forbidden outside privacy deletion.

### 4.4 Private submitter identity

`private.application_outcome_submitters` contains:

- `outcome_observation_id` primary key;
- `student_id` for privacy closure;
- `submitter_auth_user_id` when submitted by an authenticated user;
- a closed submission-channel code.

It has no external SELECT grant. Auth-user deletion may set the actor UUID to
NULL without deleting the student-owned observation. Student privacy deletion
removes the entire row.

### 4.5 `public.application_outcome_reviews`

One terminal review per observation:

- `outcome_review_id uuid PK`;
- composite application/student/observation identity;
- `decision`: VERIFIED or REJECTED;
- `verification_level` required only for VERIFIED;
- closed `reason_code` appropriate to the decision;
- `review_request_id uuid` for idempotency;
- `reviewed_at`;
- unique `outcome_observation_id`.

VERIFIED review reason codes are limited to `EVIDENCE_MATCHED` and
`SOURCE_CONFIRMED`. REJECTED reason codes are limited to
`INSUFFICIENT_EVIDENCE`, `CONFLICTING_EVIDENCE`, and `INVALID_EVIDENCE`.

`private.application_outcome_reviewers` stores the reviewer Auth UUID and has
no external read grant. Review rejects the observation submitter and requires
the dedicated signed `application_outcome_reviewer` claim. The Financial
reviewer claim provides no authority.

### 4.6 Selection history and current head

`public.application_outcome_selections` is append-only and contains:

- `outcome_selection_id uuid PK`;
- application/student identity;
- selected observation and its VERIFIED review;
- copied outcome code and verification level;
- optional same-application predecessor selection;
- `selected_at`.

`public.application_outcome_heads` contains one controlled pointer per
application to the current selection. It is the only mutable outcome pointer;
updates occur only inside the review/selection function under an application
row lock. A head cannot point to a rejected, unreviewed, cross-application, or
superseded observation.

The verified transition matrix is:

| Current selected outcome | Allowed next selected outcome |
|---|---|
| none | any closed outcome code |
| UNKNOWN | any outcome code |
| WAITLISTED | WAITLISTED, ADMITTED, REJECTED, WITHDRAWN, NO_DECISION |
| ADMITTED | ADMITTED only |
| REJECTED | REJECTED only |
| WITHDRAWN | WITHDRAWN only |
| NO_DECISION | NO_DECISION only |

A future source-correction workflow for changing one terminal result into a
different terminal result is deliberately deferred. It requires a new
additive contract rather than an unrestricted admin bypass.

Lifecycle projection after verified selection:

- WAITLISTED or UNKNOWN keeps the application SUBMITTED;
- ADMITTED or REJECTED moves it to DECIDED;
- WITHDRAWN moves it to WITHDRAWN;
- NO_DECISION moves it to CLOSED_NO_DECISION.

Unverified or rejected reports never change the application lifecycle.

### 4.7 Research-consent event chain

`public.application_research_consent_events` records append-only decisions for
future model research:

- consent event ID, application ID, and student ID;
- GRANTED or WITHDRAWN;
- nonblank policy version;
- client request UUID;
- optional predecessor consent event;
- occurred-at timestamp.

`public.application_research_consent_heads` points to the current event under
the same lock discipline. Consent is application-specific in v023. It does not
authorize training by itself; a future model phase must define extraction,
withdrawal, retention, and previously trained-model handling.

Operational application tracking and research consent are separate. Withdrawal
does not falsify or erase the operational application outcome, while student
privacy deletion removes both.

## 5. Controlled function surface

Proposed public functions:

```text
create_student_application_v023(...typed arguments...) -> application_id
update_student_application_draft_v023(...typed arguments...) -> void
cancel_student_application_draft_v023(application_id, request_id) -> void
submit_student_application_v023(...pinned IDs..., request_id) -> snapshot result
report_application_outcome_v023(...typed arguments...) -> observation_id
list_application_outcome_review_queue_v023(limit, cursor) -> bounded rows
get_application_outcome_review_candidate_v023(observation_id) -> bounded row
review_application_outcome_v023(...typed arguments...) -> review/selection result
record_application_research_consent_v023(...typed arguments...) -> consent_event_id
```

Contracts:

- typed scalar/enum arguments only; no arbitrary JSON authorization payload;
- every owner command derives `auth.uid()` and verifies ownership inside the
  function;
- every command acquires locks before re-reading mutable state;
- same request ID plus identical semantic payload returns the original result;
- same request ID plus different payload fails closed;
- review obtains reviewer identity and claim from the signed JWT context;
- no function accepts caller-supplied actor, reviewer, verification time,
  fingerprint, or lifecycle state;
- review and selection are atomic when VERIFIED;
- functions emit student lifecycle audit events with typed object/event codes.

Draft cancellation locks the student and application, proves the application
is still DRAFT and has no dependent semantic row, and transitions it to
CANCELLED with `cancellation_request_id` and closure time. The retained
terminal row makes network retry idempotent. Submitted applications can never
use this path. A submitted application's WITHDRAWN state is reached only from
a reviewed WITHDRAWN outcome observation, not from a separate lifecycle RPC.

The two reviewer-read functions require the dedicated reviewer claim, enforce
bounded stable pagination or one exact observation, and return only program
version, normalized round code, reported outcome, source kind, decision date,
evidence-hash presence, and report time. They never return student/profile
identity, submitter Auth UUID, raw evidence, storage paths, Fit details, or
Eligibility details.

Authenticated owners may execute create/update/submit/withdraw/report/consent.
Only authenticated users with `application_outcome_reviewer=true` may execute
the bounded reviewer reads and review. Anonymous, authenticator, service_role,
catalog executor, and evaluation executor receive no direct
application/outcome DML.

Function ownership may reuse `foundation_student_executor` because every row
is student-owned and must participate in the existing privacy lifecycle. The
review RPC remains claim-gated and does not grant the caller executor-role
membership.

## 6. RLS and grants

- enable and force RLS where compatible with existing executor patterns;
- authenticated SELECT only when `current_user_owns_student(student_id)`;
- no authenticated INSERT/UPDATE/DELETE table grants;
- no public or anon access;
- foundation student executor receives only the table privileges needed by
  controlled functions and privacy cascade;
- private submitter/reviewer tables have no external SELECT;
- revoke function EXECUTE from PUBLIC, anon, service_role, authenticator, and
  unrelated foundation roles before granting the exact caller set;
- add an exact authenticated-function whitelist assertion to test 014.

Reviewers receive no table-level SELECT. Their only read authority is the two
bounded claim-gated reviewer RPCs.

Migration installation must reuse the frozen PostgreSQL role-compatibility
contract established by 012/013/015: PostgreSQL 15 behavior remains unchanged,
PostgreSQL 16+ membership options are applied only where supported, the
original installer role is captured and restored without a naked
`RESET ROLE`, and temporary executor schema `CREATE` is revoked before commit.
Migration 023 must not modify hosted Supabase platform default ACLs. It revokes
implicit function EXECUTE on its own functions and proves the resulting exact
whitelist instead.

Owner-visible review rows expose decision, level, reason code, and time, but
never the reviewer Auth UUID.

## 7. Locking and concurrency

Every mutation follows this order:

1. `private.lock_student_lifecycle(student_id)`;
2. student row, if required by the existing helper;
3. application row `FOR UPDATE`;
4. submission snapshot/head row;
5. current outcome selection and predecessor observation/review rows;
6. consent head and predecessor event;
7. insert/update the target rows.

All application mutation functions use the existing student lifecycle lock,
so `delete_student_data()` serializes before the privacy cascade without
changing its public signature. Direct DML is unavailable, eliminating an
unlocked writer path.

Concurrency tests must prove:

- duplicate create/submit/report/review retries converge to one semantic row;
- two reviews of one observation produce one terminal review;
- two verified successors cannot branch from one selected head;
- privacy deletion versus submit/report/review serializes and leaves either a
  committed valid operation or complete deletion, never an orphan;
- a stale reviewer cannot replace a head selected after their snapshot read.

## 8. Privacy deletion

All public and private v023 tables are student-owned and cascade from
`students` or `student_applications`. Migration 023 must replace only the
current `private.close_student_owned_rows(uuid)` definition, preserving its
identity, owner, callers, search path, and all 001–019 checks while appending an
exhaustive v023 anti-join inventory.

It must not replace `public.delete_student_data(uuid,text)` or invent a second
student lock/deletion path.

The deletion test proves zero remaining applications, snapshots,
observations, actor links, reviews, selections, heads, consent events, and
consent heads. Only the existing non-linkable deletion tombstone may remain.

Because v023 stores no raw evidence object or storage locator, it does not
claim to solve binary evidence deletion. Any later evidence storage feature
must extend the deletion contract and remote smoke before release.

## 9. Audit and observability separation

Student application/outcome lifecycle events go to
`private.student_lifecycle_audit`, which is deleted with the student. They do
not use global `public.audit_events` because that table is not a student-owned
privacy boundary.

Infrastructure telemetry records only aggregate endpoint/error/latency data
under the Phase 4 observability plan. Migration 023 creates no generic log,
trace, session, analytics, or event-ingestion framework.

## 10. Fail-closed rules

- no outcome before the application is submitted;
- no draft cancellation after submission or after any dependent semantic row
  exists;
- no submission with DRAFT/mismatched profile or intent;
- no submission with incomplete, wrong-version, wrong-student, or
  wrong-program evaluation;
- no post-submission mutation of pinned application fields;
- no review without a dedicated claim and distinct submitter/reviewer;
- no VERIFIED review without an allowed verification level;
- no document/portal/email evidence source without a valid content hash;
- no selected outcome without its exact VERIFIED review;
- no cross-application supersession or selection;
- no terminal-state reopening in v023;
- no NULL used to mean UNKNOWN and no UNKNOWN interpreted as NO_DECISION;
- no consent inferred from reporting an outcome;
- no model/training eligibility flag inferred from verification or consent;
- retired future program/catalog changes do not rewrite the sealed submission
  snapshot.

## 11. Compatibility and migration execution

- migrations `001`–`018` remain byte-for-byte unchanged;
- v023 is additive except for the bounded replacement of the private privacy
  closure helper and additive grants/policies;
- existing Eligibility/Fit rows and APIs are unchanged;
- no new values are added to existing enums;
- a single transaction is expected to be sufficient because every enum is new;
- any need for a transaction split discovered during implementation returns to
  runner-gate review before SQL is accepted;
- no backfill creates synthetic applications or outcomes from existing Fit or
  Eligibility evaluations.

## 12. Required test matrix

Reserved test `014` must cover:

### Schema and version pins

- exact enums, tables, columns, keys, checks, indexes, and discriminator;
- completed Eligibility v0.2 and Fit v0.1 same-owner/same-program submission;
- copied values and canonical application fingerprint;
- all mismatched version/profile/program/build/fingerprint attacks.

### Lifecycle and idempotency

- DRAFT → CANCELLED and DRAFT → SUBMITTED → each permitted terminal path;
- WAITLISTED and UNKNOWN follow-up transitions;
- terminal reopening rejection;
- identical retry convergence and request-ID payload-conflict rejection;
- post-submit field mutation rejection.

### Outcome authority

- self-report remains unselected before review;
- submitter self-review rejection;
- wrong reviewer claim and reused Financial reviewer claim rejection;
- VERIFIED atomic review/selection and REJECTED non-selection;
- evidence-kind/hash shape checks;
- cross-application and branching supersession attacks.

### RLS and ACL

- owner read, unrelated-user zero rows, anon zero rows;
- zero direct external DML;
- exact function caller whitelist;
- no private actor identity exposure;
- evaluator/catalog executors have no application/outcome authority.

### Installer and hosted defaults

- PostgreSQL 15 and PostgreSQL 17 dual-role installer stacks restore the
  captured installer after executor-owned DDL;
- no naked `RESET ROLE` occurs;
- hosted default ACL rows remain byte-for-byte unchanged;
- authenticated EXECUTE equals the prior whitelist plus exactly the approved
  v023 owner/reviewer functions;

### Privacy and concurrency

- deletion removes every v023 public/private row and retains only the existing
  non-linkable tombstone;
- deletion races with create, submit, report, review, selection, and consent;
- concurrent review/head and consent-head updates serialize;
- no orphan actor, review, selection, or head rows.

### Upgrade/regression

- clean PostgreSQL 15 and target PostgreSQL 17 `001→023`;
- populated `022→023` with completed Eligibility/Fit history unchanged;
- ordered SQL suites `001`–`014`;
- Eligibility 12/12, Fit 14/14, adapter 8/8;
- existing four-function anonymous/authenticated remote smoke unchanged;
- new Application/Outcome remote smoke with complete cleanup after explicit
  implementation/deployment authorization.

## 13. Explicit exclusions

- Competitiveness features, labels, training extracts, weights, models,
  calibration, uncertainty estimates, or inference APIs;
- recommendation or portfolio tables;
- institutional aggregate outcome claims;
- automated scraping of school portals or email;
- raw evidence/document storage;
- generalized audit, analytics, workflow, queue, or plugin frameworks;
- bulk historical imports or applications lacking the complete v023 submission
  snapshot;
- changes to Phase 3 result semantics;
- implementation or deployment of Migration 023.

## 14. Approval gate

Before SQL implementation, an independent review must mechanically close:

- exact DDL and enum vocabulary;
- composite ownership and same-program constraints;
- canonical fingerprint field order;
- outcome transition and correction policy;
- reviewer claim and actor privacy;
- idempotency semantics;
- complete RLS/ACL inventory;
- lock order and privacy-deletion closure;
- research-consent product/legal wording;
- raw evidence storage exclusion;
- clean/upgrade/remote test plan.

Until that review and explicit implementation authorization, Migration 023
remains a provisional planning identity only.
