# Data model

## Identity and time

`programs` is the stable identity. `program_versions` stores cycle-specific
facts. The timing columns are deliberately separate:

- `admission_cycle_start_year` and `admission_cycle_end_year`: normalized
  admissions-cycle bounds; `admission_cycle` is generated
- `academic_year_start` and `academic_year_end`: normalized academic-year
  bounds; `academic_year` is generated
- `entry_term` and `entry_year`: when the cohort starts
- `program_deadlines.deadline_date`: when an application is due
- `valid_from` and `valid_to`: when a version was considered current

Joint delivery and the one primary administrative relationship are represented
only by `program_schools.relationship_role`. The program row contains no second
primary-school field.

## Canonical facts and evidence

Typed columns in the catalog tables are the only values consumed by
applications. `field_observations` is an immutable claims/history ledger, not
a second application data source.

A populated evidence-backed field has this path:

```text
source -> evidence_item -> field_observation
       -> canonical_field_selection -> typed catalog column
```

`select_field_observation()` maps an immutable observation to a real record and
column, updates the typed value, and changes the canonical selection in one
transaction. `KNOWN` writes the evidence-backed value. A non-known state such
as `SOURCE_CONFLICT` or `STALE` writes `NULL` while retaining the selected
state. `accept_field_observation()` remains a stricter convenience wrapper for
`KNOWN` observations.

Direct canonical updates and physical deletes are blocked. New canonical
inserts have deferred evidence-coverage checks, allowing the record and its
observations to be assembled in one transaction while rejecting a commit with
unsupported populated fields. Records are removed from active use through
audited `retire_catalog_record()` calls, not deletion. Historically important
foreign keys use restrictive deletion behavior.

Evidence items and observations are append-only. Corrections create a new
observation and may reference the superseded observation. Catalog changes are
recorded in append-only `audit_events`.

## Unknowns

Unknown facts use `NULL`, never zero, false, or an estimate. The observation
ledger explains the null with one of:

- `UNKNOWN`
- `NOT_PUBLICLY_DISCLOSED`
- `NOT_YET_RESEARCHED`
- `NOT_YET_VERIFIED`
- `NOT_APPLICABLE`
- `SOURCE_CONFLICT`
- `STALE`

`KNOWN` observations require both a value and evidence.

## Derived and external data

`program_derived_features` is separate from source facts and requires
`model_version` and `calculated_at`.

`external_metrics` requires all of:

- source granularity
- applicability (`DIRECT`, `CONTEXT_ONLY`, `NOT_APPLICABLE`, or `UNKNOWN`)
- population scope
- applicability rationale
- evidence

Institution, school, CIP, credential-field, and national occupation metrics
therefore cannot silently become program facts. Undergraduate metrics must
also identify their undergraduate population scope.

## NYU MSQE golden record

Verified canonical facts include:

- New York University UNITID `193900`
- CIP `45.0603`
- 10-month duration
- 33 total credits
- STEM status
- July start
- capstone requirement
- 18 named required courses totaling 27 credits, with 6 additional elective
  credits documented by the Bulletin
- GRE or GMAT as alternative ways to satisfy the required standardized test
- admissions stated by NYU to be on a rolling basis
- general deadline of February 15, 2026

The application page explicitly associates its admissions claims with the
2026–27 cycle. The GSAS Economics page independently corroborates the test
policy and February 15 summer-admission deadline.

No source conflicts are present in this release.

### Unverified or undisclosed fields

The following typed values remain `NULL`:

- delivery mode — `NOT_YET_VERIFIED`
- full-time classification — `NOT_YET_VERIFIED`
- minimum and average GPA — `NOT_PUBLICLY_DISCLOSED` on captured pages
- GRE quantitative minimum and average — `NOT_PUBLICLY_DISCLOSED` on captured
  pages
- TOEFL and IELTS score minimums — `NOT_YET_VERIFIED`
- application fee — `NOT_YET_VERIFIED`
- tuition, mandatory fees, living cost, and total cost — `NOT_YET_VERIFIED`
- scholarship availability — `NOT_YET_VERIFIED`

No admissions prerequisites are seeded because no exact admissions-level
prerequisite statement was verified. Course descriptions mentioning assumed
mathematical preparation are not treated as admissions requirements.

## Refresh procedure

1. Create a new source/evidence item with retrieval and verification times.
2. Add a field observation; never edit an old observation.
3. If official sources conflict, add each claim and mark the unresolved state
   without selecting either value.
4. After review, select the current observation through
   `select_field_observation()`; selecting an unresolved state clears the
   canonical typed value.
5. For a new admissions cycle, create a new `program_versions` row and attach
   new admissions, deadline, cost, course, and evidence records.
