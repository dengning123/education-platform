-- Disposable populated pre-026 fixture. It represents a valid-shape frozen
-- historical v0.1 evaluation row so the additive 025->026 upgrade can prove
-- that existing evaluation identity and fingerprints are not rewritten.

set session_replication_role = replica;

select public.create_student('a2610000-0000-4000-8000-000000000001');

insert into public.student_profile_versions (
  profile_version_id, student_id, version_number, status,
  snapshot_hash, frozen_at, product_managed, profile_revision
) values (
  'a2610000-0000-4000-8000-000000000011',
  'a2610000-0000-4000-8000-000000000001',
  1, 'FROZEN', repeat('a', 64), '2026-08-25T00:00:00Z', true, 1
);

insert into public.program_requirement_rule_sets (
  rule_set_id, program_version_id, rule_set_version,
  taxonomy_release_code, rule_schema_version, engine_contract_version,
  status, verification_evidence_id, verified_by, verified_at
) values (
  'a2610000-0000-4000-8000-000000000021',
  '00000000-0000-0000-0000-000000000401',
  2610, 'v0.1', 'phase2-v0.1', 'eligibility-v0.1',
  'VERIFIED',
  (select evidence_id from public.evidence_items order by evidence_id limit 1),
  'phase026-populated-fixture', '2026-08-25T00:00:00Z'
);

insert into public.eligibility_evaluations (
  evaluation_id, profile_version_id, rule_set_id, taxonomy_release_code,
  evaluator_name, evaluator_version, evaluator_build_hash,
  input_schema_version, profile_snapshot_hash, evaluation_state,
  input_fingerprint, outcome, root_truth_value,
  created_at, evaluated_at, inputs_sealed_at
) values (
  'a2610000-0000-4000-8000-000000000031',
  'a2610000-0000-4000-8000-000000000011',
  'a2610000-0000-4000-8000-000000000021',
  'v0.1', 'phase026-upgrade-probe', '0.1.0', repeat('b', 64),
  'eligibility-v0.1', repeat('a', 64), 'COMPLETED',
  repeat('c', 64), 'ELIGIBLE', 'SATISFIED',
  '2026-08-25T00:00:00Z', '2026-08-25T00:01:00Z',
  '2026-08-25T00:00:30Z'
);

set session_replication_role = origin;
